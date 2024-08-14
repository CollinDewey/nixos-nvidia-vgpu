{ nixpkgs }: let
    pkgs = import nixpkgs { system = "x86_64-linux"; };
    wdys-version = "552.55";
    release-version = "17.2";
in pkgs.stdenv.mkDerivation {
  pname = "NVIDIA-Windows-x86_64-${wdys-version}-patched";
  version = wdys-version;
  nativeBuildInputs = [ pkgs.which pkgs.p7zip pkgs.mscompress pkgs.osslsigncode pkgs.mono ];
  src = pkgs.fetchFromGitHub {
    owner = "VGPU-Community-Drivers";
    repo = "vGPU-Unlock-patcher";
    rev = "8f19e550540dcdeccaded6cb61a71483ea00d509";
    hash = "sha256-TyZkZcv7RI40U8czvcE/kIagpUFS/EJhVN0SYPzdNJM=";
    fetchSubmodules = true;
  };
  driver_src = pkgs.fetchurl {
    url = "https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU${release-version}/${wdys-version}_grid_win10_win11_server2022_dch_64bit_international.exe";
    sha256 = "sha256-nKlpbefK/DV+ocBQxwU+qj4D7zAsb0VLxYWMfLCrRHw=";
  };
  buildPhase = ''
    mkdir -p $out
    cd $TMPDIR
    cp -a $src/* .
    cp -a $driver_src ${wdys-version}_grid_win10_win11_server2022_dch_64bit_international.exe
    substituteInPlace patch.sh \
      --replace-fail "-t http://timestamp.digicert.com" ""
    bash ./patch.sh --create-cert wsys
    cp -ra NVIDIA-Windows-x86_64-${wdys-version}-patched/*.dll $out
  '';
}
