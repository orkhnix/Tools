# kakathic

[ -e $HOME/bin/zip ] || ( echo "Install Xu_install zip"; exit; )
[ -e $HOME/bin/aapt ] || ( echo "Install Xu_install aapt"; exit; )
[ -e $HOME/bin/aapt2 ] || ( echo "Install Xu_install aapt2"; exit; )
[ -e $HOME/bin/jdk ] || ( echo "Install Xu_install jdk"; exit; )
[ -e $HOME/bin/busybox ] || ( echo "Install Xu_install busybox"; exit; )

Taive "https://github.com/kikfox/kikfox/raw/main/bin/$1.jar" $HOME/lib/Tools/$1.jar
Taive "https://github.com/kakathic/Tools/raw/Vip/Library/$1/$1" $HOME/bin/$1
mkdir -p $HOME/tmp/prebuilt/linux
echo 'exec $HOME/bin/aapt "$@"' > $HOME/tmp/prebuilt/linux/aapt
echo 'exec $HOME/bin/aapt2 "$@"' > $HOME/tmp/prebuilt/linux/aapt2
echo 'exec $HOME/bin/aapt "$@"' > $HOME/tmp/prebuilt/linux/aapt_64
echo 'exec $HOME/bin/aapt2 "$@"' > $HOME/tmp/prebuilt/linux/aapt2_64
cd $HOME/tmp
zip -qr -9 $HOME/lib/Tools/$1.jar -d prebuilt/windows/* prebuilt/macosx/*
zip -qr -9 $HOME/lib/Tools/$1.jar prebuilt/*
[ -e $HOME/lib/Tools/$1.jar ] && echo > $HOME/ck/$1$pb
