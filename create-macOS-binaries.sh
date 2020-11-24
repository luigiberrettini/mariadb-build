#!/bin/bash

function releaseMariaDbBinaryDistribution {
    local mariaDbVersion=${1}
    local mariaDbSeries=${2}
    local macOsMinVerToSupport=${3}
    local gitHubCredentials=${4}
    local bintrayCredentials=${5}
    local bintraySubject=${6}
    local bintrayRepo=${7}
    local bintrayPackage=${8}
    local force=0; if [ -n "${9}" ] && [ "${9}" != '0' ]; then force=1; fi
    local overwrite=0; if [ -n "${10}" ] && [ "${10}" != '0' ]; then overwrite=1; fi
    if [ "$#" -lt 8 ]; then echo 'Illegal number of arguments'; return 1; fi

    echo '############################## Initializing'
    local workingDir=$(getRootDir)/work
    mkdir -p $workingDir
    echo "workingDir: $workingDir"
    prepareForPackageInstallation $workingDir

    echo '############################## Installing basic package dependencies'
    installPackageDependencies jq >/dev/null 2>&1
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi

    echo '############################## Determining the latest version for each MariaDB series'
    getMariaDbLatestVersionPerSeries \
        mariaDbLatestVersionPerSeries \
        $gitHubCredentials \
        && echo $mariaDbLatestVersionPerSeries
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi

    echo '############################## Determining MariaDB version and series'
    mariaDbVersion=$(getMariaDbVersion "$mariaDbLatestVersionPerSeries" $mariaDbVersion $mariaDbSeries)
    mariaDbSeries=$(getMariaDbSeries $mariaDbVersion)
    echo "MariaDB $mariaDbVersion ($mariaDbSeries series)"

    echo '############################## Checking if a MariaDB build was requested for the latest version of the series'
    ensureMariaDbVersionIsTheMostRecent \
        $mariaDbVersion \
        "$mariaDbLatestVersionPerSeries" \
        $force
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi

    echo '############################## Preparing for execution'
    local macOsSdkDir=$workingDir/macossdk/$macOsMinVerToSupport
    local openSslSourceDir=$workingDir/openssl/src
    local openSslCompiledDir=$workingDir/openssl/compiled
    local mariaDbSourceDir=$workingDir/mariadb/$mariaDbVersion/src
    local mariaDbBuildDir=$workingDir/mariadb/$mariaDbVersion/build
    local mariaDbCompiledDir=$workingDir/mariadb/$mariaDbVersion/compiled
    local mariaDbPackagePath=$workingDir/mariadb/$mariaDbVersion/packaged/mariadb-macos-$mariaDbVersion.tar.gz
    local mariaDbVerifiedDir=$workingDir/mariadb/$mariaDbVersion/verified
    local bintrayVersion="$mariaDbVersion"
    local bintrayFilesPrefix=$(basename $mariaDbPackagePath)
    echo "macOsSdkDir: $macOsSdkDir"
    echo "openSslSourceDir: $openSslSourceDir"
    echo "openSslCompiledDir: $openSslCompiledDir"
    echo "mariaDbSourceDir: $mariaDbSourceDir"
    echo "mariaDbBuildDir: $mariaDbBuildDir"
    echo "mariaDbCompiledDir: $mariaDbCompiledDir"
    echo "mariaDbPackagePath: $mariaDbPackagePath"
    echo "mariaDbVerifiedDir: $mariaDbVerifiedDir"
    echo "bintrayVersion: $bintrayVersion"
    echo "bintrayFilesPrefix: $bintrayFilesPrefix"

    echo '############################## Checking if the MariaDB version has no released binary distribution'
    ensureBinaryDistributionHasNeverBeenReleased \
        distributionCleanupNeeded \
        $mariaDbVersion \
        $bintrayCredentials \
        $bintraySubject \
        $bintrayRepo \
        $bintrayPackage \
        $bintrayVersion \
        $bintrayFilesPrefix \
        $overwrite
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi

    echo '############################## Installing build related package dependencies'
    installPackageDependencies \
        jemalloc \
        traildb/judy/judy \
        cmake \
        boost \
        gnutls

    echo '############################## Installing the latest SDK for the minimum macOS version to support'
    installMacOsSdk \
        $gitHubCredentials \
        $macOsMinVerToSupport \
        $macOsSdkDir
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi

    echo '############################## Installing the latest stable version of OpenSSL for this version of MariaDB'
    installOpenSsl \
        $workingDir \
        $mariaDbSeries \
        $gitHubCredentials \
        $macOsMinVerToSupport \
        $macOsSdkDir \
        $openSslSourceDir \
        $openSslCompiledDir
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi

    echo '############################## Building MariaDB from sources'
    buildMariaDb \
        $workingDir \
        $mariaDbVersion \
        $mariaDbSeries \
        $macOsMinVerToSupport \
        $macOsSdkDir \
        $openSslCompiledDir \
        $mariaDbSourceDir \
        $mariaDbBuildDir \
        $mariaDbCompiledDir \
        $mariaDbPackagePath \
        $mariaDbVerifiedDir
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi

    echo '############################## Publishing MariaDB binaries'
    publishMariaDbBinaries \
        $mariaDbVersion \
        $mariaDbPackagePath \
        $bintrayCredentials \
        $bintraySubject \
        $bintrayRepo \
        $bintrayPackage \
        $bintrayVersion \
        $bintrayFilesPrefix \
        $distributionCleanupNeeded
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi
}

function getRootDir {
    local scriptDir=$(dirname "${BASH_SOURCE[0]}")

    local repoDir="$scriptDir"
    while [ $(ls -Ald "$repoDir/.git" 2>/dev/null | wc -l) -eq 0 ]; do
        repoDir="$repoDir/.."
    done
    pushd $repoDir/.. >/dev/null
    local rootDir=$(pwd)
    popd >/dev/null
    echo "$rootDir"
}

function prepareForPackageInstallation {
    local workingDir=${1}
    if [ "$#" -ne 1 ]; then echo 'Illegal number of arguments'; return 1; fi

    startShowingProgress $workingDir
    brew update >$workingDir/brew-update-out-log.txt 2>$workingDir/brew-update-err-log.txt
    brew cleanup >$workingDir/brew-cleanup-out-log.txt 2>$workingDir/brew-cleanup-err-log.txt
    stopShowingProgress $workingDir
    cat $workingDir/brew-update-err-log.txt
    cat $workingDir/brew-cleanup-err-log.txt
}

function installPackageDependencies {
    tappedRepos=$(brew tap)
    for package in "$@"; do
        repoToTap=$(dirname $package)
        if [ "$repoToTap" != '.' ] && ! echo "$tappedRepos" | grep -iq "$repoToTap"; then
            brew tap "$repoToTap" >/dev/null
        fi
        formula=$(basename $package)
        if ! brew list --versions $formula | grep -q $formula; then
            brew install $formula | grep -v '# 100.0%'
        fi
    done
}

function getMariaDbLatestVersionPerSeries {
    local resultVar=${1}
    local gitHubCredentials=${2}
    if [ "$#" -ne 2 ]; then echo 'Illegal number of arguments'; return 1; fi

    local mariaDbTagsUrl='https://api.github.com/repos/MariaDB/server/git/refs/tags'
    local mariaDbLatestStableVersionJqExpr='map(.ref | ltrimstr("refs/tags/"))
        | map(select(. | test("^mariadb-\\d+\\.\\d+\\.\\d+$")) | ltrimstr("mariadb-") | split("."))
        | map({ version: (.[0] + "." + .[1] + "." + .[2]), series: (.[0] + "." + .[1]), major: .[0], minor: .[1], patch: .[2] })
        | group_by(.series)
        | sort_by((.[0].major | tonumber), (.[0].minor | tonumber))
        | map({ series: .[0].series, latestVersion: . | sort_by(-(.patch | tonumber)) | .[0].version })
        | map(.latestVersion)'
    queryApi mariaDbLatestStableVersions "$gitHubCredentials" "$mariaDbTagsUrl" "$mariaDbLatestStableVersionJqExpr"
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi

    eval $resultVar="'$mariaDbLatestStableVersions'"
}

function getMariaDbVersion {
    local mariaDbLatestVersionPerSeries=${1}
    local mariaDbVersion=${2}
    local mariaDbSeries=${3}
    if [ "$#" -lt 2 ]; then echo 'Illegal number of arguments'; return 1; fi

    if [ "$mariaDbVersion" == 'latest' ]; then
        if [ "$#" -ne 3 ]; then echo 'Illegal number of arguments'; return 1; fi
        echo "$mariaDbLatestVersionPerSeries" | jq -r '.[]' | grep "$mariaDbSeries"
    else
        echo "$mariaDbVersion"
    fi
}

function getMariaDbSeries {
    local mariaDbVersion=${1}
    if [ "$#" -ne 1 ]; then echo 'Illegal number of arguments'; return 1; fi

    echo $mariaDbVersion | sed -E 's/^([0-9]+\.[0-9]+)\.[0-9]+$/\1/'
}

function ensureMariaDbVersionIsTheMostRecent {
    local mariaDbVersion=${1}
    local mariaDbLatestStableVersions=${2}
    local force=${3}
    if [ "$#" -ne 3 ]; then echo 'Illegal number of arguments'; return 1; fi

    if echo "$mariaDbLatestStableVersions" | jq -r '.[]' | grep -q "$mariaDbVersion"; then
        echo "MariaDB $mariaDbVersion is the most recent version of the series"
        echo 'Proceeding with the build'
        return 0
    fi

    echo "MariaDB $mariaDbVersion is not the most recent version of the series"
    if [ $force -eq 1 ]; then
        echo 'Proceeding with the build (force flag set)'
        return 0
    fi
    echo 'Stopping the build'
    return 1
}

function ensureBinaryDistributionHasNeverBeenReleased {
    local distributionCleanupNeededResultVar=${1}
    local mariaDbVersion=${2}
    local bintrayCredentials=${3}
    local bintraySubject=${4}
    local bintrayRepo=${5}
    local bintrayPackage=${6}
    local bintrayVersion=${7}
    local bintrayFilesPrefix=${8}
    local overwrite=${9}
    if [ "$#" -ne 9 ]; then echo 'Illegal number of arguments'; return 1; fi

    local filesUrl="https://api.bintray.com/packages/$bintraySubject/$bintrayRepo/$bintrayPackage/versions/$bintrayVersion/files"
    local distributionStatusJqExpr='(arrays | map(select(.name | test("^'"$bintrayFilesPrefix"'.chunk-a$"))) | length)
        // (if . | has("message") and (.message | test("^Version '"'$bintrayVersion'"' was not found$")) then -1 else null end)'
    queryApi distributionStatus "$bintrayCredentials" "$filesUrl" "$distributionStatusJqExpr"
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi

    if [ $distributionStatus -eq -1 ]; then
        echo "A binary distribution for MariaDB $mariaDbVersion has never been released"
        echo 'Proceeding with the build (no cleanup needed)'
        eval $distributionCleanupNeededResultVar=0
        return 0
    fi

    if [ $distributionStatus -eq 0 ]; then
        echo "A binary distribution for MariaDB $mariaDbVersion has never been released"
        echo 'Proceeding with the build (some cleanup needed)'
        eval $distributionCleanupNeededResultVar=1
        return 0
    fi

    if [ $distributionStatus -eq 1 ]; then
        echo "A binary distribution for MariaDB $mariaDbVersion has already been released"
        if [ $overwrite -eq 1 ]; then
            echo 'Proceeding with the build (overwrite flag set)'
            eval $distributionCleanupNeededResultVar=1
            return 0
        fi
        echo 'Stopping the build'
        eval $distributionCleanupNeededResultVar=1
        return 1
    fi

    echo 'Unsupported distribution status'
    return 1
}

function installMacOsSdk {
    local gitHubCredentials=${1}
    local macOsMinVerToSupport=${2}
    local macOsSdkDir=${3}
    if [ "$#" -ne 3 ]; then echo 'Illegal number of arguments'; return 1; fi

    echo '########## Determining download URL'
    local sdkReleasesUrl='https://api.github.com/repos/phracker/MacOSX-SDKs/releases/latest'
    local minVerToSupportLatestSdkUrlJqExpr='.assets
        | map(select(.name | test("^MacOSX'"$macOsMinVerToSupport"'.sdk.tar.xz$")))[0]
        | .browser_download_url'
    queryApi sdkUrl "$gitHubCredentials" "$sdkReleasesUrl" "$minVerToSupportLatestSdkUrlJqExpr"
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi

    echo '########## Downloading and extracting'
    mkdir -p $macOsSdkDir && curl -s -S -L -X GET "$sdkUrl" | tar -C $macOsSdkDir -Jx --strip 1
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi
}

function installOpenSsl {
    local workingDir=${1}
    local mariaDbSeries=${2}
    local gitHubCredentials=${3}
    local macOsMinVerToSupport=${4}
    local macOsSdkDir=${5}
    local openSslSourceDir=${6}
    local openSslCompiledDir=${7}
    if [ "$#" -ne 7 ]; then echo 'Illegal number of arguments'; return 1; fi

    echo '########## Determining download URL'
    local openSslTagsUrl='https://api.github.com/repos/openssl/openssl/git/refs/tags'
    if [ "$mariaDbSeries" == '5.1' ] || [ "$mariaDbSeries" == '5.2' ] || [ "$mariaDbSeries" == '5.3' ]; then
        local openSslSeries='1.0'
    else
        local openSslSeries='1.1'
    fi
    local openSslLatestStableTagUrlJqExpr='map(.ref | ltrimstr("refs/tags/") | ascii_downcase | sub("_"; "-") | gsub("_"; "."))
        | map(select(. | test("^openssl-\\d+\\.\\d+\\.\\d+\\w{0,1}$")))
        | map({ version: . | ltrimstr("openssl-"), series: . | sub("^openssl-(?<series>\\d+\\.\\d+)\\.\\d+\\w{0,1}$"; .series)})
        | group_by(.series)
        | map({ series: .[0].series, latestVersion: [ .[].version ] | sort | reverse | .[0] })
        | map(select(.series | test("'"$openSslSeries"'")))
        | map(.latestVersion)
        | "https://www.openssl.org/source/openssl-" + .[0] + ".tar.gz"'
    queryApi openSslUrl "$gitHubCredentials" "$openSslTagsUrl" "$openSslLatestStableTagUrlJqExpr"
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi

    echo '########## Downloading and extracting'
    mkdir -p $openSslSourceDir
    curl -s -S -L -X GET "$openSslUrl" | tar -C $openSslSourceDir -zx --strip 1
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi

    pushd $openSslSourceDir >/dev/null
    mkdir -p $openSslCompiledDir

    echo '########## Configuring'
    if [ "$openSslSeries" == '1.0' ]; then
        ./Configure \
            darwin64-x86_64-cc \
            no-shared \
            --prefix=$openSslCompiledDir \
            --openssldir=$openSslCompiledDir/bin \
            -mmacosx-version-min=$macOsMinVerToSupport \
            >/dev/null
        sed -i'.bak' -e "s|^CFLAG=|CFLAG=-isysroot $macOsSdkDir |" Makefile
        sed -i'.bak' -e "s|^SHARED_LDFLAGS=|SHARED_LDFLAGS=-isysroot $macOsSdkDir |" Makefile
        local returnValue=$?; if [ $returnValue -ne 0 ]; then popd >/dev/null; return $returnValue; fi
    else
        OSX_DEPLOYMENT_TARGET="$macOsMinVerToSupport" \
        ./Configure \
            darwin64-x86_64-cc \
            no-shared \
            --prefix=$openSslCompiledDir \
            --openssldir=$openSslCompiledDir \
            CFLAGS="-isysroot $macOsSdkDir -mmacosx-version-min=$macOsMinVerToSupport" \
            LDFLAGS="-isysroot $macOsSdkDir" \
            >/dev/null
        local returnValue=$?; if [ $returnValue -ne 0 ]; then popd >/dev/null; return $returnValue; fi
    fi

    echo '########## Compiling'
    startShowingProgress $workingDir
    make >$workingDir/openssl-make-log.txt 2>&1
    local returnValue=$?
    stopShowingProgress $workingDir
    if [ $returnValue -ne 0 ]; then cat $workingDir/openssl-make-log.txt; popd >/dev/null; return $returnValue; fi

    echo '########## Testing'
    startShowingProgress $workingDir
    make test >$workingDir/openssl-test-log.txt 2>&1
    local returnValue=$?
    stopShowingProgress $workingDir
    cat $workingDir/openssl-test-log.txt | grep 'OpenSSL 1.0\|Result'
    if [ $returnValue -ne 0 ]; then cat $workingDir/openssl-test-log.txt; popd >/dev/null; return $returnValue; fi

    echo '########## Installing'
    startShowingProgress $workingDir
    make install >$workingDir/openssl-install-log.txt 2>&1
    local returnValue=$?
    stopShowingProgress $workingDir
    if [ $returnValue -ne 0 ]; then cat $workingDir/openssl-install-log.txt; popd >/dev/null; return $returnValue; fi

    popd >/dev/null
}

function buildMariaDb {
    local workingDir=${1}
    local mariaDbVersion=${2}
    local mariaDbSeries=${3}
    local macOsMinVerToSupport=${4}
    local macOsSdkDir=${5}
    local openSslCompiledDir=${6}
    local mariaDbSourceDir=${7}
    local mariaDbBuildDir=${8}
    local mariaDbCompiledDir=${9}
    local mariaDbPackagePath=${10}
    local mariaDbVerifiedDir=${11}
    if [ "$#" -ne 11 ]; then echo 'Illegal number of arguments'; return 1; fi

    echo '########## Downloading and extracting'
    local mariaDbUrl="https://downloads.mariadb.com/MariaDB/mariadb-${mariaDbVersion}/source/mariadb-${mariaDbVersion}.tar.gz"
    mkdir -p $mariaDbSourceDir
    curl -s -S -L -X GET "$mariaDbUrl" | tar -C $mariaDbSourceDir -zx --strip 1
    local returnValue=$?; if [ $returnValue -ne 0 ]; then popd >/dev/null; return $returnValue; fi
    if [ -f $mariaDbSourceDir/storage/mroonga/vendor/groonga/vendor/download_lz4.rb ]; then
        pushd $mariaDbSourceDir/storage/mroonga/vendor/groonga/vendor >/dev/null
        ./download_lz4.rb
        popd >/dev/null
    fi

    mkdir -p $mariaDbBuildDir
    if [ "$mariaDbSeries" == '5.1' ] || [ "$mariaDbSeries" == '5.2' ] || [ "$mariaDbSeries" == '5.3' ]; then
        pushd $mariaDbSourceDir >/dev/null
    else
        pushd $mariaDbBuildDir >/dev/null
    fi

    echo '########## Preparing for compilation'
    mkdir -p $mariaDbCompiledDir
    if [ "$mariaDbSeries" == '5.1' ] || [ "$mariaDbSeries" == '5.2' ] || [ "$mariaDbSeries" == '5.3' ]; then
        sed -i'.bak' -e 's/$RM "$cfgfile"/$RM -f "$cfgfile"/' $mariaDbSourceDir/configure
        CFLAGS='-O3' \
        CPPFLAGS="-I$openSslCompiledDir/include" \
        CXXFLAGS='-O3' \
        LDFLAGS="-L$openSslCompiledDir/lib" \
        OSX_DEPLOYMENT_TARGET="$macOsMinVerToSupport" \
        ./configure \
            --prefix=$mariaDbCompiledDir \
            --enable-assembler \
            --enable-local-infile \
            --with-ssl=$openSslCompiledDir \
            --with-charset=utf8 \
            --with-extra-charsets=complex \
            --with-collation=utf8_general_ci \
            --with-readline \
            --with-plugins=max-no-ndb \
            --with-plugin-xtradb \
            --with-plugin-innodb_plugin \
            --without-plugin-oqgraph \
            --with-mysqld-ldflags=-static \
            --with-client-ldflags=-static \
            --with-big-tables \
            --with-libevent=bundled \
            --with-zlib-dir=bundled \
            >/dev/null
        if [ -f $mariaDbSourceDir/include/mysql.h.pp ]; then
            sed -i'.bak' -e '/^#include/d' $mariaDbSourceDir/include/mysql.h.pp
        fi
        if [ -f $mariaDbSourceDir/include/mysql/client_plugin.h.pp ]; then
            sed -i'.bak' -e '/^#include/d' $mariaDbSourceDir/include/mysql/client_plugin.h.pp
        fi
        if [ -f $mariaDbSourceDir/include/mysql/plugin_auth.h.pp ]; then
            sed -i'.bak' -e '/^#include/d' $mariaDbSourceDir/include/mysql/plugin_auth.h.pp
        fi
        if [ -f $mariaDbSourceDir/vio/viosocket.c ]; then
            # The \ and new line after the 'a' are required
            sed -i'.bak' \
                -e '/^#include "vio_priv\.h"/a \
                    #include <netinet/tcp.h>' $mariaDbSourceDir/vio/viosocket.c
        fi
    elif [ "$mariaDbSeries" == '5.5' ]; then
        cmake $mariaDbSourceDir \
            -DBUILD_CONFIG=mysql_release \
            -DWITH_JEMALLOC=no \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=$macOsMinVerToSupport \
            -DCMAKE_OSX_SYSROOT=$macOsSdkDir \
            -DCMAKE_SKIP_RPATH=YES \
            -DWITH_SSL=bundled \
            -DCMAKE_INSTALL_PREFIX=$mariaDbCompiledDir \
            -DWITHOUT_TOKUDB_STORAGE_ENGINE=ON \
            -DDEFAULT_CHARSET=UTF8 \
            -DDEFAULT_COLLATION=utf8_general_ci \
            -DWITH_READLINE=ON \
            -DCMAKE_C_FLAGS='-Wno-deprecated-declarations' \
            -Wno-dev \
            -DWITH_UNIT_TESTS=ON \
            >/dev/null
    else
        # -DSKIP_TESTS=ON needed to disable Connector/C tests that require a running server
        cmake $mariaDbSourceDir \
            -DBUILD_CONFIG=mysql_release \
            -DWITH_JEMALLOC=$(find $(brew --cellar)/jemalloc -maxdepth 2 -type d -name include) \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=$macOsMinVerToSupport \
            -DCMAKE_OSX_SYSROOT=$macOsSdkDir \
            -DCMAKE_MACOSX_RPATH=OFF \
            -DWITH_SSL=$openSslCompiledDir \
            -DOPENSSL_ROOT_DIR=$openSslCompiledDir \
            -DOPENSSL_INCLUDE_DIR=$openSslCompiledDir/include \
            -DOPENSSL_LIBRARIES=$openSslCompiledDir/lib/libssl.a \
            -DCRYPTO_LIBRARY=$openSslCompiledDir/lib/libcrypto.a \
            -DCMAKE_INSTALL_PREFIX=$mariaDbCompiledDir \
            -DWITHOUT_TOKUDB=1 \
            -DDEFAULT_CHARSET=UTF8 \
            -DDEFAULT_COLLATION=utf8_general_ci \
            -DWITH_PCRE=bundled \
            -DWITH_READLINE=ON \
            -DGRN_WITH_BUNDLED_LZ4=yes \
            -DCMAKE_C_FLAGS='-Wno-deprecated-declarations' \
            -Wno-dev \
            -DSKIP_TESTS=ON \
            >/dev/null
        sed -i'.bak' -e '/test-connect.sh/d' $mariaDbBuildDir/CMakeFiles/Makefile.cmake
        sed -i'.bak' -e '/embedded/d' $mariaDbBuildDir/CTestTestfile.cmake
    fi
    local returnValue=$?; if [ $returnValue -ne 0 ]; then popd >/dev/null; return $returnValue; fi

    echo '########## Compiling'
    startShowingProgress $workingDir
    LC_ALL=C make >$workingDir/mariadb-make-log.txt 2>&1
    local returnValue=$?
    stopShowingProgress $workingDir
    if [ $returnValue -ne 0 ]; then cat $workingDir/mariadb-make-log.txt; popd >/dev/null; return $returnValue; fi

    echo '########## Testing'
    local returnValue=0
    startShowingProgress $workingDir
    if [ "$mariaDbSeries" == '5.1' ] || [ "$mariaDbSeries" == '5.2' ] || [ "$mariaDbSeries" == '5.3' ]; then
        pushd $mariaDbSourceDir/mysql-test >/dev/null
        if ! ./mysql-test-run.pl --force --parallel=8 --skip-rpl >$workingDir/mariadb-test-log.txt 2>&1; then returnValue=1; fi
        popd >/dev/null
    else
        make test >$workingDir/mariadb-test-log.txt 2>&1
        returnValue=$?
    fi
    stopShowingProgress $workingDir
    if [ $returnValue -eq 0 ]; then
        cat $workingDir/mariadb-test-log.txt | grep 'failed out of\|were successful'
    else
        cat $workingDir/mariadb-test-log.txt
    fi

    echo '########## Installing'
    startShowingProgress $workingDir
    make install >$workingDir/mariadb-install-log.txt 2>&1
    local returnValue=$?
    stopShowingProgress $workingDir
    if [ $returnValue -ne 0 ]; then cat $workingDir/mariadb-install-log.txt; popd >/dev/null; return $returnValue; fi

    echo '########## Packaging binaries'
    mkdir -p $(dirname $mariaDbPackagePath)
    tar -C $mariaDbCompiledDir -chf $mariaDbPackagePath ./

    echo '########## Verifying binaries'
    mkdir -p $mariaDbVerifiedDir
    tar -C $mariaDbVerifiedDir -xf $mariaDbPackagePath
    local mysqlInstallDbPath=$(find $mariaDbVerifiedDir -maxdepth 2 -type f -name mysql_install_db)
    $(dirname $mysqlInstallDbPath)/mysql_install_db \
        --no-defaults \
        --basedir=$mariaDbVerifiedDir \
        --datadir=$mariaDbVerifiedDir/data \
        --force \
        --skip-name-resolve
    local returnValue=$?; if [ $returnValue -ne 0 ]; then popd >/dev/null; return $returnValue; fi

    popd >/dev/null
}

function publishMariaDbBinaries {
    local mariaDbVersion=${1}
    local mariaDbPackagePath=${2}
    local bintrayCredentials=${3}
    local bintraySubject=${4}
    local bintrayRepo=${5}
    local bintrayPackage=${6}
    local bintrayVersion=${7}
    local bintrayFilesPrefix=${8}
    local distributionCleanupNeeded=${9}
    if [ "$#" -ne 9 ]; then echo 'Illegal number of arguments'; return 1; fi

    local bintraySubjectRepoPackage="$bintraySubject/$bintrayRepo/$bintrayPackage"

    if [ $distributionCleanupNeeded -eq 0 ]; then
        echo '########## Creating Bintray version'
        local createVersionUrl="https://api.bintray.com/packages/$bintraySubjectRepoPackage/versions"
        local createVersionBody="{ \"name\": \"$bintrayVersion\", \"desc\": \"MariaDB $mariaDbVersion macOS binary distribution\" }"
        local response=$(curl -s -S -L -i -X POST \
            -H 'Content-Type: application/json' \
            --data "$createVersionBody" \
            -u "$bintrayCredentials" \
            "$createVersionUrl" \
            2>&1)
        echo "$response" | grep -iq '201 Created'
        local returnValue=$?
        if [ $returnValue -ne 0 ]; then
            echo "Bintray package '/packages/$bintraySubjectRepoPackage': unable to create version $bintrayVersion"
            printf "Response\n$response\n"
            return $returnValue
        fi
    fi

    echo '########## Retrieving binary archive info'
    echo "Name: $(basename $mariaDbPackagePath)"
    echo "Size: $(du -h $mariaDbPackagePath | awk '{ print $1 }' | sed -E 's/^([0-9]+)(M|G)$/\1 \2iB/')"

    echo '########## Splitting binary archive in 200 MiB chunks to avoid hitting Bintray upload limit'
    split -b 200m -a 1 $mariaDbPackagePath $mariaDbPackagePath.chunk-
    local returnValue=$?; if [ $returnValue -ne 0 ]; then popd >/dev/null; return $returnValue; fi
    for file in $mariaDbPackagePath.chunk-?; do basename $file; done

    echo '########## Uploading files to Bintray'
    local bintrayNameSedExpr="s/$(basename $mariaDbPackagePath)/$bintrayFilesPrefix/"
    for file in $mariaDbPackagePath.*; do
        local localName=$(basename $file)
        local bintrayName=$(echo $localName | sed -E "$bintrayNameSedExpr")
        local sha1Checksum=$(shasum -a 1 $file | awk '{ print $1 }')
        local sha256Checksum=$(shasum -a 256 $file | awk '{ print $1 }')
        echo "### $localName"
        echo "Bintray name: $bintrayName"
        echo "SHA1: $sha1Checksum"
        echo "SHA256: $sha256Checksum"

        local uploadContentUrl="https://api.bintray.com/content/$bintraySubjectRepoPackage/$bintrayVersion/$bintrayName"
        local uploadContentQueryString="publish=1&override=$distributionCleanupNeeded"
        local response=$(curl -s -S -L -i -X PUT \
            -H "X-Checksum-Sha1:$sha1Checksum" \
            -H "X-Checksum-Sha2:$sha256Checksum" \
            -T "$file" \
            -u "$bintrayCredentials" \
            "$uploadContentUrl?$uploadContentQueryString" \
            2>&1)
        echo "$response" | grep -iq '201 Created'
        local returnValue=$?
        if [ $returnValue -ne 0 ]; then
            echo "Bintray package '/packages/$bintraySubjectRepoPackage': unable to upload content '$bintrayVersion/$bintrayName'"
            printf "Response\n$response\n"
            return $returnValue
        fi
    done
}

function startShowingProgress {
    local workingDir=${1}
    if [ "$#" -ne 1 ]; then echo 'Illegal number of arguments'; return 1; fi

    touch $workingDir/flag-file
    while true; do sleep 4; if [ -f $workingDir/flag-file ]; then printf '.'; else break; fi; done &
}

function stopShowingProgress {
    local workingDir=${1}
    if [ "$#" -ne 1 ]; then echo 'Illegal number of arguments'; return 1; fi

    rm $workingDir/flag-file
    sleep 6
    printf '\n'
}

function queryApi {
    local resultVar=${1}
    local credentials=${2}
    local url=${3}
    local jqExpression=${4}
    if [ "$#" -ne 4 ]; then echo 'Illegal number of arguments'; return 1; fi

    local onelineJqExpression=$(echo $jqExpression | tr -d '\n' | sed -E 's/\s{2}//g')

    local curlResult=0 # declaration and assignment split to prevent $? from being always 0
    curlResult=$(curl -s -S -L -X GET -u "$credentials" "$url" 2>&1)
    if [ $? -ne 0 ]; then
        echo "Unable to query '$url' and parse response with the jq expression '$onelineJqExpression'"
        echo "curlResult: $curlResult"
        return 1
    fi

    local jqResult=0 # declaration and assignment split to prevent $? from being always 0
    jqResult=$(echo $curlResult | jq -r "$jqExpression" 2>&1)
    if [ $? -ne 0 ] || [ "$result" == 'null' ]; then
        echo "Unable to query '$url' and parse response with the jq expression '$onelineJqExpression'"
        echo "curlResult: $curlResult"
        echo "jqResult: $jqResult"
        return 1
    fi

    eval $resultVar="'$jqResult'"
}