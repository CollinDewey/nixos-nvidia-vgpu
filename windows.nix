{ nixpkgs }: let
    pkgs = import nixpkgs { system = "x86_64-linux"; };
    wdys-version = "538.46";
    release-version = "16.5";
in pkgs.stdenv.mkDerivation {
  pname = "NVIDIA-Windows-x86_64-${wdys-version}-patched";
  version = wdys-version;
  nativeBuildInputs = [ pkgs.which pkgs.p7zip pkgs.mscompress pkgs.osslsigncode pkgs.mono ];
  src = pkgs.fetchFromGitHub {
    owner = "VGPU-Community-Drivers";
    repo = "vGPU-Unlock-patcher";
    rev = "59c75f98baf4261cf42922ba2af5d413f56f0621";
    hash = "sha256-IUBK+ni+yy/IfjuGM++4aOLQW5vjNiufOPfXOIXCDeI=";
    fetchSubmodules = true;
  };
  driver_src = pkgs.fetchurl {
    url = "https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU${release-version}/${wdys-version}_grid_win10_win11_server2019_server2022_dch_64bit_international.exe";
    sha256 = "sha256-GHD2kVo1awyyZZvu2ivphrXo2XhanVB9rU2mwmfjXE4=";
  };
  buildPhase = ''
    mkdir -p $out
    cd $TMPDIR
    cp -a $src/* .
    cp -a $driver_src ${wdys-version}_grid_win10_win11_server2019_server2022_dch_64bit_international.exe
    substituteInPlace patch.sh \
      --replace-fail "-t http://timestamp.digicert.com" ""
    bash ./patch.sh --create-cert wsys
    cp -ra NVIDIA-Windows-x86_64-${wdys-version}-patched/*.dll $out
  '';
}
