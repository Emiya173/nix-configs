{ base }:

base.overrideAttrs (previousAttrs: {
  # Reuse immutable profile paths as cache keys instead of querying Nix on every run.
  patches = (previousAttrs.patches or [ ]) ++ [ ./nix-profile-cache.patch ];
})
