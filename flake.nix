{
  description = "Open RTL synthesis framework and tools";
  nixConfig.bash-prompt = "[nix(openXC7)] ";

  # Nixpkgs / NixOS version to use.
  inputs.nixpkgs.url = "nixpkgs/nixos-22.11";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs = { self, nixpkgs, flake-utils, ... }:
    let

      # to work with older version of flakes
      lastModifiedDate =
        self.lastModifiedDate or self.lastModified or "19700101";

      # Generate a user-friendly version number.
      version = builtins.substring 0 8 lastModifiedDate;

      # System types to support.
      supportedSystems =
        [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlay ];
        });

      lib = nixpkgs.lib;

    in {
      # A Nixpkgs overlay.
      overlay = final: prev: rec {
        ghdl = prev.ghdl;

        abc-verifier = prev.abc-verifier.overrideAttrs (_: rec {
          version = "yosys-0.17";
          src = final.fetchFromGitHub {
            owner = "yosyshq";
            repo = "abc";
            rev = version;
            hash = "sha256-+1UcYjK2mvhlTHl6lVCcj5q+1D8RUTquHaajSl5NuJg=";
          };
        });

        yosys-ghdl = prev.yosys-ghdl;

        yosys = prev.yosys.overrideAttrs (prevAttr: rec {
          version = "0.17";

          src = final.fetchFromGitHub {
            owner = "yosyshq";
            repo = "yosys";
            rev = "${prevAttr.pname}-${version}";
            hash = "sha256-IjT+G3figWe32tTkIzv/RFjy0GBaNaZMQ1GA8mRHkio=";
          };

          doCheck = false; # FIXME(ac): can we turn these back on?

          passthru = {
            inherit (prevAttr) withPlugins;
            allPlugins = { ghdl = yosys-ghdl; };
          };
        });

        nextpnr-xilinx = with final;
          stdenv.mkDerivation rec {
            pname = "nextpnr-xilinx";
            version = "0.5.0";

            srcs = [
              (fetchgit {
                url = "https://github.com/openXC7/nextpnr-xilinx";
                rev = version;
                fetchSubmodules = true;
                deepClone = false;
                hash = "sha256-mDYEmq3MW1kK9HeR4PyGmKQnAzpvlOf+H66o7QTFx3k=";
                leaveDotGit = false;
              })
            ];

            sourceRoot = "nextpnr-xilinx";

            nativeBuildInputs = [ cmake git ];
            buildInputs = [ python310Packages.boost python310 eigen ]
              ++ (lib.optional stdenv.cc.isClang llvmPackages.openmp);

            setupHook = ./nextpnr-setup-hook.sh;

            cmakeFlags = [
              "-DCURRENT_GIT_VERSION=${
                lib.substring 0 7 (lib.elemAt srcs 0).rev
              }"
              "-DARCH=xilinx"
              "-DBUILD_GUI=OFF"
              "-DBUILD_TESTS=OFF"
              "-DUSE_OPENMP=ON"
            ];

            installPhase = ''
              mkdir -p $out/bin
              cp nextpnr-xilinx bba/bbasm $out/bin/
              mkdir -p $out/usr/share/nextpnr/external
              cp -rv ../xilinx/external/prjxray-db $out/usr/share/nextpnr/external/
              cp -rv ../xilinx/external/nextpnr-xilinx-meta $out/usr/share/nextpnr/external/
              cp -rv ../xilinx/python/ $out/usr/share/nextpnr/python/
              cp ../xilinx/constids.inc $out/usr/share/nextpnr
            '';

            doCheck = false;

            meta = with lib; {
              description = "Place and route tool for FPGAs";
              homepage = "https://github.com/openXC7/nextpnr-xilinx";
              license = licenses.isc;
              platforms = platforms.all;
              maintainers = with maintainers; [ thoughtpolice ];
            };
          };

        prjxray = with final;
          stdenv.mkDerivation rec {
            pname = "prjxray";
            version = "76401bd93e493fd5ff4c2af4751d12105b0f4f6d";

            srcs = [
              (fetchgit {
                url = "https://github.com/f4pga/prjxray";
                rev = "76401bd93e493fd5ff4c2af4751d12105b0f4f6d";
                fetchSubmodules = true;
                deepClone = false;
                hash = "sha256-+k9Em+xX1rWPs3oATy3g1U0O6y3CATT9P42p0YCafxM=";
                leaveDotGit = false;
              })
            ];

            setupHook = ./prjxray-setup-hook.sh;

            nativeBuildInputs = [ cmake git ];
            buildInputs = [ python310Packages.boost python310 eigen ];

            installPhase = ''
              mkdir -p $out/bin
              cp -v tools/xc7frames2bit tools/xc7patch $out/bin
              mkdir -p $out/usr/share/python3/
              cp -rv $srcs/prjxray $out/usr/share/python3/
            '';

            doCheck = false;

            meta = with lib; {
              description = "Xilinx series 7 FPGA bitstream documentation";
              homepage = "https://github.com/f4pga/prjxray";
              license = licenses.isc;
              platforms = platforms.all;
              maintainers = with maintainers; [ thoughtpolice ];
            };
          };

        nextpnr-xilinx-chipdb = {
          artiz7 = prev.callPackage ./nix/nextpnr-xilinx-chipdb.nix {
            backend = "artiz7";
          };
          kintex7 = prev.callPackage ./nix/nextpnr-xilinx-chipdb.nix {
            backend = "kintex7";
          };
          spartan7 = prev.callPackage ./nix/nextpnr-xilinx-chipdb.nix {
            backend = "spartan7";
          };
          zynq7 = prev.callPackage ./nix/nextpnr-xilinx-chipdb.nix {
            backend = "zynq7";
          };
        };
      };

      # Provide some binary packages for selected system types.
      packages = forAllSystems (system: {
        inherit (nixpkgsFor.${system})
          yosys ghdl yosys-ghdl prjxray nextpnr-xilinx
          nextpnr-xilinx-chipdb # FIXME: testing
          abc-verifier;
      });

      # The default package for 'nix build'. This makes sense if the
      # flake provides only one package or there is a clear "main"
      # package.
      defaultPackage = forAllSystems (system: self.packages.${system}.yosys);

      devShell = forAllSystems (system:
        nixpkgsFor.${system}.mkShell {
          buildInputs = with nixpkgsFor.${system}; [
            yosys
            ghdl
            yosys-ghdl
            prjxray
            nextpnr-xilinx
          ];
        });
    };
}
