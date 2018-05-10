#!/data/data/com.termux/files/usr/bin/env bash

## Written by revel/monoidic, all rites reversed, five tons of flax, yadda yadda yadda
## May or may not be heavily based on other such scripts
## May contain outdated links

## TODO: there's so many exceptions... Do something about that

#https://nixos.org/nix/install
#https://alpha.gnu.org/gnu/guix/guix-binary-0.14.0.aarch64-linux.tar.xz
#https://mirror.leaseweb.com/devuan/devuan_ascii_beta/embedded/devuan_ascii_2.0.0-beta_arm64_raspi3.tar.gz

#set -x
set -e

availabledists="alpine, arch, fedora, gentoo, slackware, ubuntu, void"
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

getarch() {
	case "`getprop ro.product.cpu.abi`" in
		arm64-v8a) arch=aarch64	;;
		armeabi*) arch=armhf ;;
		x86_64) arch=x86_64 ;;
		x86) arch=x86 ;;
		*)
			printf 'Unknown arch "%s", exiting\n' "`getprop ro.product.cpu.abi`"
			exit 1
			;;
	esac
}

printusage() {
	cat <<- EOM
		Welcome to the Termux prefix multi-installer
		This tool will save the prefixes in ~/prefixes
		and the scripts to enter the prefixes in ~/bin
		What would you like to install?
		(The selection marked in [square brackets] is the default)
		Available prefixes:
		$availabledists
	EOM
}

distroselect() {
	while true; do case "$selection" in
		[Aa][Ll]*) install=alpine
			releases="[3.7], edge"
			break ;;
		[Aa][Rr]*) install=arch
			releases="[current]"
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
		[Vv]*) install=void
			releases="[musl], glibc"
			break ;;
		[Qq]*) exit ;;
		*)
			echo "Not available (enter q to exit)"
			read selection ;;
	esac; done
}

releaseselect() {
	if [ $install = alpine ]; then case "$_release" in
			[Ee]*) release="edge" ;;
			*3*|*7*|*) release="v3.7" ;;
		esac
	elif [ $install = arch ]; then release="current"
	elif [ $install = fedora ]; then case "$_release" in
			*7*) release="27"; secondaryopt="1.6" ;;
			*6*|*) release="26"; secondaryopt="1.5" ;;
		esac
	elif [ $install = gentoo ]; then release="current"
	elif [ $install = slackware ]; then release="current"
	elif [ $install = ubuntu ]; then case "$_release" in
			*14*|[Tt]*) release="trusty" ;;
			*16*|[Xx]*) release="xenial" ;;
			*18*|[Bb]*) release="bionic" ;;
			*17*|[Aa]*|*) release="artful" ;;
		esac
	elif [ $install = void ]; then case "$_release" in
			[Gg]*) release="glibc" ;;
			*) release="musl" ;;
		esac
	fi
}

prefixexists() {
	echo "This prefix already exists. Would you like to remove it first?"
	echo -en "(no will attempt to overwrite it in-place)\n(Yn)"
	read rmprefix
	case "$rmprefix" in
		[Nn]*) : ;;
		[Yy]*|*) chmod -R 777 "$prefixdir"; rm -rf "$prefixdir" ;;
	esac
}

dldata() {
	if [ $install = alpine ]; then
		tarurl="https://nl.alpinelinux.org/alpine/${release}/releases/${arch}/alpine-minirootfs-3.7.0-${arch}.tar.gz"
		sumurl="${tarurl}.sha512"
		sum="sha512sum"
	elif [ $install = arch ]; then
		if [ $arch = armhf ]; then arch=armv7
		elif [[ $arch =~ x86 ]]; then error "idk, arch mirrors don't have any easy-to-keep-track-of way of marking mirrors for you"
		fi
		tarurl="https://mirror.dotsrc.org/archlinuxarm/os/ArchLinuxARM-${arch}-latest.tar.gz"
		sumurl="${tarurl}.md5"
		sum="md5sum"
	elif [ $install = fedora ]; then
		if [ $arch = x86 ]; then echo "No x86 fedora image available"; exit 1
		elif [ $arch = armhf ]; then arch=armhfp
		elif [ $arch = aarch64 ]; then secdir="-secondary"
		fi
		baseurl="https://download.fedoraproject.org/pub/fedora${secdir}/releases/${release}/Docker/${arch}/images/Fedora-Docker"
		tarurl="${baseurl}-Base-${release}-${secondaryopt}.${arch}.tar.xz"
		sumurl="${baseurl}-${release}-${secondaryopt}-${arch}-CHECKSUM"
		sum="sha256sum"
	elif [ $install = gentoo ]; then
		if [ $arch = aarch64 ]; then tarurl="https://gentoo.osuosl.org/experimental/arm64/stage3-arm64-20180305.tar.bz2"
		elif [ $arch = armhf ]; then arch=arm; secdir="armv7a_hardfp"
		elif [ $arch = x86_64 ]; then arch=amd64; secdir=amd64
		elif [ $arch = x86 ]; then secdir=i686
		fi
		if [ -z $tarurl ]; then
			baseurl="https://gentoo.osuosl.org/releases/${arch}/autobuilds/"
			tarurl=$(curl "${baseurl}/latest-stage3-${secdir}.txt" | grep -o "^.*stage3-${secdir}-.*.tar.\w*")
			tarurl="${baseurl}${tarurl}"
		fi
		sumurl="${tarurl}.DIGESTS"
		sum="sha512sum"
	elif [ $install = slackware ]; then
		if [[ $arch =~ x86 ]]; then error "No x86(_64) slackware image available"
		elif [ $arch = armhf ]; then
			baseurl"https://ftp.slackware.pl/pub/slackwarearm/slackwarearm-devtools/minirootfs/roots/slack-current-miniroot"
			tarurl="${baseurl}_12Apr18.tar.xz"
			sumurl="${baseurl}_details.txt"
		elif [ $arch = aarch64 ]; then
			baseurl="http://dl.fail.pp.ua/slackware/minirootfs/slack-current-aarch64-miniroot"
			tarurl="${baseurl}_14Apr18.tar.xz"
			sumurl="${baseurl}_14Apr18_details.txt"
		fi
		sum="sha1sum"
	elif [ $install = ubuntu ]; then
		if [ $arch = aarch64 ]; then arch=arm64
		elif [ $arch = x86 ]; then arch=i386
		elif [ $arch = x86_64 ];then arch=amd64
		fi
		baseurl="https://partner-images.canonical.com/core/${release}/current"
		tarurl="${baseurl}/ubuntu-${release}-core-cloudimg-${arch}-root.tar.gz"
		sumurl="${baseurl}/SHA256SUMS"
		sum="sha256sum"
	elif [ $install = void ]; then
		if [ $arch = x86 ]; then error "No rootfs for this arch available"
		elif [ $arch = armhf ]; then arch=armv7l
		fi
		[ $release = musl ] && musl="-musl"
		baseurl="https://mirror.clarkson.edu/voidlinux/live/current"
		tarurl="${baseurl}/void-${arch}${musl}-ROOTFS-20171007.tar.xz"
		sumurl="${baseurl}/sha256sums.txt"
		sum="sha256sum"
	fi
}

gentoosumfix() {
	sed -i 2q checksum
	sed -i s/-2008.0.t/-20180305.t/ checksum
}

fedoraextract() {
	tar xf $tarfile --strip-components=1 layer.tar -O | tar xp
	chmod +w .
}

regularextract() {
#	proot --link2symlink -0 tar xpf $tarfile 2> /dev/null || :
	proot -0 bsdtar -xpf $tarfile --exclude dev || :
	mkdir -p dev
}

cleanup() {
	rm -f $tarfile checksum
}

touchups() {
	username=$(id -un)
	userid=$(id -u)

	cat >> etc/group <<- EOF
		ident:x:3003:
		everybody:x:9997:
		${username}_cache:x:$((userid + 10000)):
		all_a$((userid - 10000)):x:$((userid + 40000)):
		user:x:${userid}:
	EOF
	cat >> etc/passwd <<- EOF
		user:x:${userid}:${userid}::/home:/bin/sh
	EOF
	rm -f etc/resolv.conf
	cat > etc/resolv.conf <<- EOF
		nameserver 1.1.1.1
		nameserver 1.0.0.1
	EOF
}

gentootouchups() {
	(
	cd etc/portage
	mkdir -p env package.env package.use profile
	cat >> make.conf <<- EOF
		CFLAGS="-O2 -pipe -march=native"
		CXXFLAGS="\${CFLAGS}"
		MAKEOPTS="-j4"
		GENTOO_MIRRORS="https://mirror.dkm.cz/gentoo/"

		## unnecessary and powerless inside proot
		USE="\${USE} -caps -filecaps -suid"
	EOF
	cat > profile/packages <<- EOF
		## unnecessary and pointless in proot
		-*virtual/dev-manager
		-*virtual/udev
		-*virtual/service-manager
		-*virtual/modutils
		-*sys-fs/e2fsprogs
	EOF
	cat > package.use/termux <<- EOF
		## won't compile otherwise
		sys-libs/glibc suid
		## use an external iptables if you're rooted, please
		sys-apps/iproute2 -iptables
		## useless in proot
		sys-apps/debianutils -installkernel
	EOF
	cat <<- EOM
		You'll probably need root and to mount /dev/shm
		as tmpfs and chmod it to 1777 to have *everything* work properly...
		Also, tweak the MAKEOPTS in make.conf if you want, I guess
	EOM
	)
}

entryscript() {
	echo "Creating entry script in ~/bin"
	mkdir -p bin
	script="bin/start-${install}-${release}"
	cat > "$script" <<- EOF
		#!/bin/bash

		unset LD_PRELOAD
		#--link2symlink

		pr_exec="exec proot "
		## root shell unless you pass any argument (maybe make it more complex lol)
		pr_exec+="\$([ -z \$@ ] && echo "-0") "
		## set root to the root of the prefix
		pr_exec+="-r $(realpath "$prefixdir") "
		## bind all that good stuff
		pr_exec+="-b $HOME -b /dev -b /proc -b /storage -b /sys -w / "
		## add stuff to the environment
		pr_exec+="/usr/bin/env -i HOME=/root TERM=\$TERM LANG=en_US.UTF-8 "
		pr_exec+="PATH=/bin:/usr/bin:/sbin:/usr/sbin "
		## bash unless it's alpine
		pr_exec+="$([ $install = alpine ] && echo "/bin/sh " || echo "/bin/bash ")"
		## login shell
		pr_exec+="--login"
		\$pr_exec
	EOF

	termux-fix-shebang "$script"
	chmod +x "$script"
}



## beginning
cd
chkpak proot wget tar bsdtar coreutils grep curl
getarch


if [ "$1" ]; then
	selection="$1"
else
	printusage
	read selection
fi

distroselect

if [ $releases = "[current]" ]; then :
elif [ "$2" ]; then
	_release="$2"
else
	echo -e "Select a release:\n${releases}"
	read _release
fi

releaseselect


prefixdir="prefixes/${install}-${release}"

if [ -d "$prefixdir" ]; then
	prefixexists
fi


mkdir -p "$prefixdir"
cd "$prefixdir"
echo "Downloading archive and checksums..."


dldata


wget $tarurl && wget $sumurl -O checksum || error "Error fetching files"

[ $install = gentoo ] && gentoosumfix

$sum --ignore-missing --check checksum || error "Checksum error"
tarfile=*.tar.*

echo -e "\nExtracting prefix..."

if [ $install = fedora ]; then
	fedoraextract
else
	regularextract
fi

cleanup

echo "Adding users/groups/DNS..."
touchups

[ $install = gentoo ] && gentootouchups

cd
entryscript

echo "Done! Execute ~/$script to enter the prefix"
