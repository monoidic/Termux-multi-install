#!/data/data/com.termux/files/usr/bin/env bash

## Written by revel, all rites reversed, five tons of flax, yadda yadda yadda
## May or may not be heavily based on other such scripts

#set -x
set -e

availabledists="alpine, fedora, gentoo, slackware, ubuntu"
## tested and didn't work very well: debian (debootstrap and experimental rootfs)

error() {
	echo "$1"
	cd
	rm -r "$prefixdir"
	exit 1
}

chkpak() {
	listinstalled=`apt list 2>/dev/null | grep installed`
	for i in $*; do

		if [[ -n $(grep $i <<< "$listinstalled") ]]; then
			echo "$i installed"
		else
			notinstpak+=" $i"
		fi
	done
	if [ -n "$notinstpak" ]; then
		cat <<- EOM
		Packages not installed:
		$notinstpak
		please install them using "dpkg install${notinstpak}"
		and then try this script again.
		EOM
		exit 1
	fi
	echo
}





cd

_arch=`getprop ro.product.cpu.abi`

case "`getprop ro.product.cpu.abi`" in
	arm64-v8a) arch=aarch64	;;
	armeabi*) arch=armhf ;;
	x86_64) arch=x86_64 ;;
	x86) arch=x86 ;;
	*)
		printf 'Unknown arch "%s", exiting\n' "$_arch"
		exit 1
		;;
esac

chkpak proot wget tar coreutils grep curl



if [ -z "$1" ]; then
	cat <<- EOM
		Welcome to the Termux prefix multi-installer
		This tool will save the prefixes in ~/prefixes
		and the scripts to enter the prefixes in ~/bin
		What would you like to install?
		(The selection marked in [square brackets] is the default)
		Available prefixes:
		$availabledists
	EOM
	read selection
else
	selection="$1"
fi

while true; do
	case "$selection" in
		[Aa]*) install=alpine
			releases="[3.7], edge"
			break ;;
		[Ff]*) install=fedora
			releases="[26], 27"
			break ;;
		[Gg]*) install=gentoo
			releases="[current]"
			break ;;
		[Ss]*) install=slackware
			releases="[current]"
			break ;;
		[Uu]*) install=ubuntu
			releases="trusty(14.04), xenial(16.04), [artful(17.10)], bionic(18.04)"
			break ;;
		[Qq]*) exit ;;
		*)
			echo "Not available (enter q to exit)"
			read selection ;;
	esac
done

echo -e "Select a release:\n${releases}"
read _release

[ $install = alpine ] && case "$_release" in
	[Ee]*) release="edge" ;;
	*3*|*7*|*) release="v3.7" ;;
esac
[ $install = fedora ] && case "$_release" in
	*7*) release="27"; secondaryopt="1.6" ;;
	*6*|*) release="26"; secondaryopt="1.5" ;;
esac
[ $install = gentoo ] && release="current"
[ $install = slackware ] && release="current"
[ $install = ubuntu ] && case "$_release" in
	*14*|[Tt]*) release="trusty" ;;
	*16*|[Xx]*) release="xenial" ;;
	*18*|[Bb]*) release="bionic" ;;
	*17*|[Aa]*|*) release="artful" ;;
esac

prefixdir="prefixes/${install}-${release}"

if [ -d "$prefixdir" ]; then
	echo "This prefix already exists. Would you like to remove it first?"
	echo -en "(no will attempt to overwrite it in-place)\n(Yn)"
	read rmprefix
	case "$rmprefix" in
		[Nn]*) : ;;
		[Yy]*|*) chmod -R 777 "$prefixdir"; rm -rf "$prefixdir" ;;
	esac
fi
mkdir -p "$prefixdir"
cd "$prefixdir"
echo "Downloading archive and checksums..."

if [ $install = alpine ]; then
	tarurl="https://nl.alpinelinux.org/alpine/${release}/releases/${arch}/alpine-minirootfs-3.7.0-${arch}.tar.gz"
	sumurl="${tarurl}.sha512"
	sum="sha512sum"
elif [ $install = fedora ]; then
	[ $arch = x86 ] && { echo "No x86 fedora image available"; exit 1; }
	[ $arch = armhf ] && arch=armhfp
	[ $arch = aarch64 ] && secdir="-secondary"
	baseurl="https://download.fedoraproject.org/pub/fedora${secdir}/releases/${release}/Docker/${arch}/images/Fedora-Docker"
	tarurl="${baseurl}-Base-${release}-${secondaryopt}.${arch}.tar.xz"
	sumurl="${baseurl}-${release}-${secondaryopt}-${arch}-CHECKSUM"
	sum="sha256sum"
elif [ $install = gentoo ]; then
	[ $arch = aarch64 ] && tarurl="https://gentoo.osuosl.org/experimental/arm64/stage3-arm64-20180305.tar.bz2"
	[ $arch = armhf ] && { arch=arm; secdir="armv7a_hardfp"; }
	[ $arch = x86_64 ] && { arch=amd64; secdir=amd64; }
	[ $arch = x86 ] && secdir=i686
	[ -z $tarurl ] {
		baseurl="https://gentoo.osuosl.org/releases/${arch}/autobuilds/"
		tarurl=$(curl "${baseurl}/latest-stage3-${secdir}.txt" | grep -o "^.*stage3-${secdir}-.*.tar.\w*")
		tarurl="${baseurl}${tarurl}"
	}
	sumurl="${tarurl}.DIGESTS"
elif [ $install = slackware ]; then
	[[ $arch =~ x86 ]] && { echo "No x86(_64) slackware image available"; exit 1; }
	[ $arch = armhf ] && {
		baseurl"https://ftp.slackware.pl/pub/slackwarearm/slackwarearm-devtools/minirootfs/roots/slack-current-miniroot"
		tarurl="${baseurl}_12Apr18.tar.xz"
		sumurl="${baseurl}_details.txt"
	}
	[ $arch = aarch64 ] && {
		baseurl="http://dl.fail.pp.ua/slackware/minirootfs/slack-current-aarch64-miniroot"
		tarurl="${baseurl}_14Apr18.tar.xz"
		sumurl="${baseurl}_14Apr18_details.txt"
	}
	sum="sha1sum"
elif [ $install = ubuntu ]; then
	[ $arch = aarch64 ] && arch=arm64
	[ $arch = x86 ] && arch=i386
	[ $arch = x86_64 ] && arch=amd64
	baseurl="https://partner-images.canonical.com/core/${release}/current"
	tarurl="${baseurl}/ubuntu-${release}-core-cloudimg-${arch}-root.tar.gz"
	sumurl="${baseurl}/SHA256SUMS"
	sum="sha256sum"
fi

wget $tarurl && wget $sumurl -O checksum || error "Error fetching files"

$sum --ignore-missing --check checksum || error "Checksum error"
tarfile=*.tar.*
echo -e "\nExtracting prefix..."
if [ $install = fedora ]; then
	tar xf $tarfile --strip-components=1 --exclude json --exclude VERSION | tar xp
	chmod +w .
else
	proot --link2symlink -0 tar xpf $tarfile 2> /dev/null || :
fi

## cleanup
rm $tarfile checksum

## touchups
echo "Adding users/groups/DNS..."
username=$(id -un)
userid=$(id -u)

cat >> etc/group <<- EOF
ident:x:3003:
everybody:x:9997:
${username}_cache:x:$((userid + 10000)):
all_a$((userid - 10000)):x:$((userid + 40000)):
user:x:${userid}:
EOF

cat >> etc/passwd << EOF
user:x:${userid}:${userid}::/home:/bin/sh
EOF

cat > etc/resolv.conf << EOF
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF

if [ $install = gentoo ]; then
	(
	cd etc/portage
	mkdir -p env package.env package.use profile
	cat >> make.conf < EOF
CFLAGS="-O2 -pipe -march=native"
CXXFLAGS="${CFLAGS}"
MAKEOPTS="-j4"
GENTOO_MIRRORS="https://mirror.dkm.cz/gentoo/"

## unnecessary and powerless inside proot
USE="-caps -filecaps -suid"
EOF
	cat > env/rootcompile << EOF
FEATURES="${FEATURES} -sandbox -usersandbox -userpriv"
EOF
	cat > profile/packages << EOF
## unnecessary and pointless in a chroot
-*virtual/dev-manager
-*virtual/udev
-*virtual/service-manager
-*virtual/modutils
EOF
	cat > package.env/termux << EOF
dev-lang/python rootcompile
EOF
	cat > package.use/termux << EOF
## won't compile otherwise
sys-libs/glibc suid
EOF
	echo "You'll probably need root and to mount /dev/shm"
	echo "as tmpfs and chmod it to 1777 to compile Python (or to just crosscompile it?)"
	echo "Haven't tested all packages myself, naturally"
	echo "Also, tweak the MAKEOPTS in make.conf if you want, I guess"
	echo "The package.env for dev-lang/python may or may not be unnecessary"
	)
fi

## entry script
cd
echo "Creating entry script in ~/bin"
mkdir -p bin
script="bin/start-${install}-${release}"
cat > "$script" << EOF
#!/bin/bash

unset LD_PRELOAD
exec proot --link2symlink \
\$([ -z \$@ ] && echo "-0") \
-r $(realpath "$prefixdir") \
-b $HOME -b /dev -b /proc -b /storage -b /sys -w / \
/usr/bin/env -i HOME=/root TERM=\$TERM LANG=en_US.UTF-8 \
PATH=/bin:/usr/bin:/sbin:/usr/sbin \
$([ $install = alpine ] && echo /bin/sh || echo /bin/bash) \
--login
EOF

termux-fix-shebang "$script"
chmod +x "$script"
echo "Done! Execute ~/$script to enter the prefix"
