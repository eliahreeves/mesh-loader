{
  description = "Dev Shell";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          platformio-core
          gnumake
          (python3.withPackages (ps:
            with ps; [
              protobuf
              grpcio
              grpcio-tools
            ]))
          esptool
          rsync
          git
          mklittlefs
          patch
          tio
        ];
        shellHook = ''
          export PLATFORMIO_CORE_DIR=$PWD/.platformio
          unset PIP_PREFIX
          unset PYTHONNOUSERSITE
          unset PYTHONHASHSEED
          unset _PYTHON_HOST_PLATFORM
          unset _PYTHON_SYSCONFIGDATA_NAME
          unset SOURCE_DATE_EPOCH

          echo "PlatformIO: $(pio --version)"
        '';
      };
    });
}
