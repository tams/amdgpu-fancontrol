{
  description =
    "Simple bash script to control AMD Radeon graphics cards fan speeds";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/master";

  outputs = { self, nixpkgs }:
    with nixpkgs; {
      defaultPackage.x86_64-linux =
        with import nixpkgs { system = "x86_64-linux"; };
        stdenv.mkDerivation {
          name = "amdgpu-fancontrol";
          version = "1.0";

          src = self;

          nativeBuildInputs = [ makeWrapper ];

          installPhase = ''
            mkdir -p $out/bin
            cp amdgpu-fancontrol $out/bin/amdgpu-fancontrol
            wrapProgram $out/bin/amdgpu-fancontrol --prefix PATH ":" ${
              lib.makeBinPath [ "$out" coreutils bc ]
            }
          '';
        };

      nixosModules = {
        amdgpu-fancontrol = { config, ... }:
          let cfg = config.services.amdgpu-fancontrol;
          in {
            options.services.amdgpu-fancontrol = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description =
                  "Service to manually define fan curve for AMG GPUs";
              };

              debug = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = ''
                  Enable debugging to syslog.

                  It is quite chatty, keep in mind before enabling.
                '';
              };

              fanCurve = lib.mkOption {
                type = lib.types.listOf (lib.types.listOf lib.types.int);
                default = [ [ 65 0 ] [ 80 153 ] [ 90 255 ] ];
                description = ''
                  Define fan curve as a list of lists following the format:

                  ```
                  [
                    [TEMP1 PWM1]
                    [TEMP2 PWM2]
                  ]
                  ```

                  Where `TEMP{N}` is a temperature in degrees Celsius, `PWM{N}` is a value between 0-255 to define
                  corresponding fan speed. Values between entries are calculated with linear interpolation.
                '';
              };
            };

            config = lib.mkIf cfg.enable {
              systemd.services.amdgpu-fancontrol = {
                description = "Fan speed management for AMD GPUs";
                wantedBy = [ "multi-user.target" ];
                path = [ self.defaultPackage.x86_64-linux ];
                serviceConfig = {
                  ExecStart =
                    "${self.defaultPackage.x86_64-linux}/bin/amdgpu-fancontrol";
                  Type = "simple";
                  Restart = "on-failure";
                };
              };

              environment.etc."amdgpu-fancontrol.cfg".text = ''
                TEMPS=(${
                  builtins.concatStringsSep " " (builtins.map
                    (x: builtins.toString ((builtins.elemAt x 0) * 1000))
                    cfg.fanCurve)
                })
                PWMS=(${
                  builtins.concatStringsSep " "
                  (builtins.map (x: builtins.toString (builtins.elemAt x 1))
                    cfg.fanCurve)
                })
                DEBUG=${if cfg.debug then "true" else "false"}
              '';
            };
          };

      };
    };

}
