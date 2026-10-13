/* Narrow, allocating FFI boundary. Every failure frees its temporary output. */
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>
#include <zstd.h>
#include <openssl/bn.h>
#include <openssl/core_names.h>
#include <openssl/evp.h>
#include <openssl/param_build.h>

enum { XL_OK = 0, XL_DATA = 1, XL_LIMIT = 2, XL_MEMORY = 3 };

static int grow(unsigned char **buffer, size_t *capacity, size_t ceiling) {
    if (*capacity >= ceiling) return XL_LIMIT;
    size_t next = *capacity > ceiling / 2 ? ceiling : *capacity * 2;
    unsigned char *p = realloc(*buffer, next);
    if (!p) return XL_MEMORY;
    *buffer = p;
    *capacity = next;
    return XL_OK;
}

static int raw_deflate(const unsigned char *src, size_t len, size_t limit,
                       unsigned char **out, size_t *capacity, size_t *written) {
    if (len > UINT_MAX) return XL_DATA;
    if (len == 0) return XL_OK; /* Matches the source decoder's empty payload. */
    z_stream stream = {0};
    stream.next_in = (Bytef *)src;
    stream.avail_in = (uInt)len;
    if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) return XL_MEMORY;
    int result = XL_DATA;
    for (;;) {
        if (*written == *capacity) {
            result = grow(out, capacity, limit + 1);
            if (result != XL_OK) break;
        }
        size_t space = *capacity - *written;
        uInt available = (uInt)(space > UINT_MAX ? UINT_MAX : space);
        stream.next_out = *out + *written;
        stream.avail_out = available;
        uInt before = stream.avail_in;
        int status = inflate(&stream, Z_SYNC_FLUSH);
        size_t produced = available - stream.avail_out;
        *written += produced;
        if (*written > limit) { result = XL_LIMIT; break; }
        if (status != Z_OK && status != Z_STREAM_END && status != Z_BUF_ERROR) {
            result = status == Z_MEM_ERROR ? XL_MEMORY : XL_DATA;
            break;
        }
        if (status == Z_STREAM_END) {
            result = stream.avail_in == 0 ? XL_OK : XL_DATA;
            break;
        }
        if (stream.avail_in == 0 && stream.avail_out != 0) {
            /* Xlog can terminate a record at Z_SYNC_FLUSH, without Z_FINISH. */
            result = len >= 4 && memcmp(src + len - 4, "\0\0\xff\xff", 4) == 0
                     ? XL_OK : XL_DATA;
            break;
        }
        if (before == stream.avail_in && produced == 0) { result = XL_DATA; break; }
    }
    inflateEnd(&stream);
    return result;
}

static int zstandard(const unsigned char *src, size_t len, size_t limit,
                     unsigned char **out, size_t *capacity, size_t *written) {
    if (len == 0) return XL_DATA;
    ZSTD_DCtx *ctx = ZSTD_createDCtx();
    if (!ctx) return XL_MEMORY;
    /* Bound decoder history independently of the advertised frame window. */
    size_t window = limit < 1024 ? 1024 : limit;
    int window_log = 10;
    while (window_log < 30 && ((size_t)1 << window_log) < window) ++window_log;
    if (ZSTD_isError(ZSTD_DCtx_setParameter(ctx, ZSTD_d_windowLogMax, window_log))) {
        ZSTD_freeDCtx(ctx);
        return XL_DATA;
    }
    ZSTD_inBuffer input = {src, len, 0};
    int result = XL_DATA;
    for (;;) {
        if (*written == *capacity) {
            result = grow(out, capacity, limit + 1);
            if (result != XL_OK) break;
        }
        ZSTD_outBuffer output = {*out, *capacity, *written};
        size_t before = input.pos;
        size_t old_written = *written;
        size_t status = ZSTD_decompressStream(ctx, &output, &input);
        *written = output.pos;
        if (*written > limit) { result = XL_LIMIT; break; }
        if (ZSTD_isError(status)) { result = XL_DATA; break; }
        if (input.pos == input.size && output.pos < output.size) {
            /* ZSTD_e_flush records need not end the frame. As in the reference,
               accept consumed input with output; this cannot prove completeness. */
            result = status == 0 || *written != 0 ? XL_OK : XL_DATA;
            break;
        }
        if (before == input.pos && old_written == *written) { result = XL_DATA; break; }
    }
    ZSTD_freeDCtx(ctx);
    return result;
}

int xlog_decompress(int codec, const unsigned char *src, size_t len, size_t limit,
                    unsigned char **out, size_t *written) {
    *out = NULL;
    *written = 0;
    if (limit == SIZE_MAX) return XL_LIMIT;
    size_t capacity = limit < 65536 ? limit + 1 : 65536;
    unsigned char *buffer = malloc(capacity);
    if (!buffer) return XL_MEMORY;
    int result = codec == 0
        ? raw_deflate(src, len, limit, &buffer, &capacity, written)
        : zstandard(src, len, limit, &buffer, &capacity, written);
    if (result == XL_OK) *out = buffer;
    else free(buffer);
    return result;
}

int xlog_shared_secret(const unsigned char *private_key, const unsigned char *public_key,
                       unsigned char *secret) {
    int result = 2;
    unsigned char encoded[65] = {4}; /* SEC1 uncompressed point prefix. */
    memcpy(encoded + 1, public_key, 64);
    BIGNUM *scalar = BN_bin2bn(private_key, 32, NULL);
    OSSL_PARAM_BLD *builder = OSSL_PARAM_BLD_new();
    OSSL_PARAM *params = NULL;
    EVP_PKEY_CTX *import = EVP_PKEY_CTX_new_from_name(NULL, "EC", NULL);
    EVP_PKEY_CTX *derive = NULL;
    EVP_PKEY *local = NULL, *peer = NULL;
    if (!scalar || !builder || !import) goto cleanup;
    if (!OSSL_PARAM_BLD_push_utf8_string(builder, OSSL_PKEY_PARAM_GROUP_NAME, "secp256k1", 0)
        || !OSSL_PARAM_BLD_push_BN(builder, OSSL_PKEY_PARAM_PRIV_KEY, scalar)) goto cleanup;
    params = OSSL_PARAM_BLD_to_param(builder);
    if (!params || EVP_PKEY_fromdata_init(import) <= 0
        || EVP_PKEY_fromdata(import, &local, EVP_PKEY_KEYPAIR, params) <= 0) goto cleanup;
    OSSL_PARAM_free(params);
    params = NULL;
    OSSL_PARAM_BLD_free(builder);
    builder = OSSL_PARAM_BLD_new();
    if (!builder
        || !OSSL_PARAM_BLD_push_utf8_string(builder, OSSL_PKEY_PARAM_GROUP_NAME, "secp256k1", 0)
        || !OSSL_PARAM_BLD_push_octet_string(builder, OSSL_PKEY_PARAM_PUB_KEY, encoded, sizeof(encoded))) goto cleanup;
    params = OSSL_PARAM_BLD_to_param(builder);
    if (!params) goto cleanup;
    if (EVP_PKEY_fromdata_init(import) <= 0
        || EVP_PKEY_fromdata(import, &peer, EVP_PKEY_PUBLIC_KEY, params) <= 0) {
        result = 1;
        goto cleanup;
    }
    derive = EVP_PKEY_CTX_new(local, NULL);
    if (!derive || EVP_PKEY_derive_init(derive) <= 0) goto cleanup;
    if (EVP_PKEY_derive_set_peer(derive, peer) <= 0) { result = 1; goto cleanup; }
    size_t size = 32;
    if (EVP_PKEY_derive(derive, secret, &size) > 0 && size == 32) result = 0;
cleanup:
    EVP_PKEY_CTX_free(derive);
    EVP_PKEY_free(peer);
    EVP_PKEY_free(local);
    EVP_PKEY_CTX_free(import);
    OSSL_PARAM_free(params);
    OSSL_PARAM_BLD_free(builder);
    BN_clear_free(scalar);
    return result;
}
