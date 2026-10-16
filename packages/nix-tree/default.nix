{ base }:

base.overrideAttrs (previousAttrs: {
  # Select v1 explicitly on Nix 2.33+, matching nix-tree's existing parser.
  patches = (previousAttrs.patches or [ ]) ++ [ ./json-format.patch ];
})
