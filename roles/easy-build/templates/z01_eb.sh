if [ -z "$EASYBUILD_PREFIX" ]; then
	export EASYBUILD_PREFIX={{ prefix_path }}
	export EASYBUILD_MODULES_TOOL=Lmod
	module load EasyBuild
fi
