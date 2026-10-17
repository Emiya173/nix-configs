{ base, python3 }:

base.overrideAttrs (previousAttrs: {
  patches = (previousAttrs.patches or [ ]) ++ [
    # Backport https://github.com/Open-Wine-Components/umu-launcher/pull/652.
    ./runtime-cdn.patch
    # Use the current version index and explicit HTTPS, keeping offline opt-out.
    ./runtime-endpoints.patch
  ];

  postCheck = (previousAttrs.postCheck or "") + ''
    ${python3.interpreter} -m unittest discover -s ${./.} -p test_runtime_updates.py
  '';
})
