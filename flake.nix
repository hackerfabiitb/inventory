{
  description = "Hackerfab IITB Inventory - Next.js + Redis development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (
        pkgs:
        let
          # Local Redis instance. Keeps its data inside the repo at ./.redis
          # so it never touches a system-wide Redis. Add .redis/ to .gitignore.
          redis-dev = pkgs.writeShellScriptBin "redis-dev" ''
            set -euo pipefail
            DATA_DIR="''${PWD}/.redis"
            mkdir -p "$DATA_DIR"
            echo "redis-dev: data in $DATA_DIR, port ''${REDIS_PORT:-6379}"
            exec ${pkgs.redis}/bin/redis-server \
              --dir "$DATA_DIR" \
              --port "''${REDIS_PORT:-6379}" \
              --appendonly yes \
              --daemonize no
          '';
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              nodejs_22 # Next.js 16 needs Node >= 20.9; 22 is current LTS
              redis # gives you redis-cli as well as redis-server
              git
              redis-dev

              # Optional extras - uncomment if you want them in the shell
              # typescript-language-server
              # nodePackages.prettier
              # jq
            ];

            # Prebuilt native binaries pulled in by npm (@next/swc-*, sharp, etc.)
            # are dynamically linked against a normal FHS glibc. On NixOS that
            # fails unless nix-ld is enabled. These two vars make nix-ld work;
            # they are harmless on non-NixOS systems and on macOS.
            NIX_LD_LIBRARY_PATH = pkgs.lib.optionalString pkgs.stdenv.isLinux (
              pkgs.lib.makeLibraryPath [
                pkgs.stdenv.cc.cc.lib
                pkgs.zlib
                pkgs.openssl
                pkgs.libuv
                pkgs.vips # sharp, used by next/image
              ]
            );
            NIX_LD = pkgs.lib.optionalString pkgs.stdenv.isLinux "${pkgs.stdenv.cc.libc}/lib/ld-linux-x86-64.so.2";

            shellHook = ''
              # Keep npm's global installs inside the repo instead of ~/.npm-global
              export NPM_CONFIG_PREFIX="$PWD/.npm-global"
              export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"

              # Next.js telemetry off by default
              export NEXT_TELEMETRY_DISABLED=1

              echo ""
              echo "  HackerFab IITB Inventory dev shell"
              echo "  node       $(node --version)   npm $(npm --version)"
              echo ""
              echo "  npm install         install dependencies"
              echo "  redis-dev           start a local Redis (data in ./.redis)"
              echo "  npm run dev         start Next.js on :3000"
              echo "  npm run build       type-check + production build"
              echo ""
            '';
          };
        }
      );
    };
}
