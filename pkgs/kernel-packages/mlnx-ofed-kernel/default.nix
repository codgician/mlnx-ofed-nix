{
  lib,
  pkgs,
  stdenv,
  kernel,
  kernelModuleMakeFlags,
  mkUnpackScript,
  mlnx-ofed-src,
  writeShellScriptBin,

  # Whether to copy source to $out/usr/src/ofa_kernel
  copySource ? true,
  ...
}:
let
  kernelVersion = kernel.modDirVersion;
  kernelDir = "${kernel.dev}/lib/modules/${kernelVersion}";
  kernelModuleInstallFlags = [ "INSTALL_MOD_PATH=${placeholder "out"}" ];
in
stdenv.mkDerivation rec {
  pname = "mlnx-ofed-kernel";
  inherit (mlnx-ofed-src) src version;

  unpackPhase = mkUnpackScript pname;

  nativeBuildInputs =
    kernel.moduleBuildDependencies
    # Mock update-alternatives in post build script
    ++ lib.optional copySource (writeShellScriptBin "update-alternatives" "true");

  patchPhase =
    ''
      patchShebangs .

      substituteInPlace ./ofed_scripts/configure \
        --replace-warn '/bin/cp' 'cp' \
        --replace-warn '/bin/rm' 'rm'
      substituteInPlace ./ofed_scripts/makefile \
        --replace-warn '/bin/ls' 'ls' \
        --replace-warn '/bin/cp' 'cp' \
        --replace-warn '/bin/rm' 'rm'
    ''
    + lib.optionalString copySource ''
      # Patch post build script so source could be copied
      # this will be needed for building other mlnx kernel modules
      substituteInPlace ./ofed_scripts/dkms_ofed_post_build.sh \
        --replace-fail '/usr/src/ofa_kernel' '${placeholder "out"}/usr/src/ofa_kernel' \
        --replace-warn '/bin/cp' 'cp' \
        --replace-warn '/bin/rm' 'rm'
    '';

  configureScript = "./configure";

  configureFlags = [
    "--with-core-mod"
    "--with-user_mad-mod"
    "--with-user_access-mod"
    "--with-addr_trans-mod"
    "--with-mlx4-mod"
    "--with-mlx4_en-mod"
    "--with-mlx5-mod"
    "--with-ipoib-mod"
    "--with-srp-mod"
    "--with-rds-mod"
    "--with-iser-mod"
    "--kernel-sources=${kernelDir}/source"
    "--with-linux=${kernelDir}/source"
    "--with-linux-obj=${kernelDir}/build"
    "--modules-dir=${kernelDir}"
    "--kernel-version=${kernelVersion}"
  ];

  # Paralellize configure phase
  preConfigure = ''
    appendToVar configureFlags "-j$NIX_BUILD_CORES"
  '';

  enableParallelBuilding = true;

  makeFlags = kernelModuleMakeFlags ++ kernelModuleInstallFlags;

  postBuild = lib.optionalString copySource ''
    # Run post build tasks
    export ofa_build_src=${placeholder "out"}/usr/src/ofa_kernel/${kernelVersion}
    ./ofed_scripts/dkms_ofed_post_build.sh
  '';

  installFlags = kernelModuleInstallFlags;

  meta = with pkgs.lib; {
    description = "Mellanox mlnx-ofed driver kernel module";
    platforms = platforms.linux;
    maintainers = with maintainers; [ codgician ];
  };
}
