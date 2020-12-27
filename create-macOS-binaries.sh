#!/bin/bash

function releaseMariaDbBinaryDistribution {
    local mariaDbVersion=${1}
    local mariaDbSeries=${2}
    local macOsMinVerToSupport=${3}
    local gitHubCredentials=${4}
    local force=0; if [ -n "${5}" ] && [ "${5}" != '0' ]; then force=1; fi
    local overwrite=0; if [ -n "${6}" ] && [ "${6}" != '0' ]; then overwrite=1; fi
    if [ "$#" -lt 4 ]; then echo 'Illegal number of arguments'; return 1; fi

    echo '############################## Initializing'
    local repoDir=$(getRepoDir)
    echo "repoDir: $repoDir"
    local workingDir=$(getRootDir "$repoDir")/work
    mkdir -p $workingDir
    echo "workingDir: $workingDir"
    local apiRepoBaseUrl=$(getApiRepoBaseUrl "$repoDir")
    echo "apiRepoBaseUrl: $apiRepoBaseUrl"
    prepareForPackageInstallation $workingDir

    echo '############################## Installing basic package dependencies'
    installPackageDependencies jq
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi

    echo '############################## Determining the latest version for each MariaDB series'
    getMariaDbLatestVersionPerSeries \
        mariaDbLatestVersionPerSeries \
        $gitHubCredentials \
        && echo $mariaDbLatestVersionPerSeries
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi

    echo '############################## Determining the latest binary distribution released for each MariaDB series'
    getMariaDbLatestBinaryDistributionPerSeries \
        mariaDbLatestDistributionPerSeries \
        $apiRepoBaseUrl \
        $gitHubCredentials \
        && echo $mariaDbLatestDistributionPerSeries
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi

    echo '############################## Determining the binary distributions to be released'
    getMariaDbBinaryDistributionsToRelease \
        mariaDbDistributionsToRelease \
        $mariaDbLatestVersionPerSeries \
        $mariaDbLatestDistributionPerSeries \
        $overwrite \
        && echo $mariaDbDistributionsToRelease
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi

    echo '############################## Determining MariaDB version and series'
    mariaDbVersion=$(getMariaDbVersion $mariaDbLatestVersionPerSeries $mariaDbVersion $mariaDbSeries)
    mariaDbSeries=$(getMariaDbSeries $mariaDbVersion)
    echo "MariaDB $mariaDbVersion ($mariaDbSeries series)"

    echo '############################## Checking if a MariaDB build was requested for the latest version of the series'
    ensureMariaDbVersionIsTheMostRecent \
        $mariaDbVersion \
        $mariaDbLatestVersionPerSeries \
        $force
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi

    echo '############################## Checking if the MariaDB version has no released binary distribution'
    ensureBinaryDistributionHasNeverBeenReleased \
        $mariaDbVersion \
        $mariaDbDistributionsToRelease \
        $overwrite
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi

    echo '############################## Installing build related package dependencies'
    installPackageDependencies \
        jemalloc \
        traildb/judy/judy \
        cmake \
        boost \
        gnutls

    echo '############################## Preparing for execution'
    local macOsSdkDir="$workingDir/macossdk/$macOsMinVerToSupport"
    local openSslSourceDir="$workingDir/openssl/src"
    local openSslCompiledDir="$workingDir/openssl/compiled"
    local mariaDbSourceDir="$workingDir/mariadb/$mariaDbVersion/src"
    local mariaDbBuildDir="$workingDir/mariadb/$mariaDbVersion/build"
    local mariaDbCompiledDir="$workingDir/mariadb/$mariaDbVersion/compiled"
    local mariaDbPackagePath="$workingDir/mariadb/$mariaDbVersion/packaged/mariadb-$mariaDbVersion-macos.tar.gz"
    local mariaDbVerifiedDir="$workingDir/mariadb/$mariaDbVersion/verified"
    echo "macOsSdkDir: $macOsSdkDir"
    echo "openSslSourceDir: $openSslSourceDir"
    echo "openSslCompiledDir: $openSslCompiledDir"
    echo "mariaDbSourceDir: $mariaDbSourceDir"
    echo "mariaDbBuildDir: $mariaDbBuildDir"
    echo "mariaDbCompiledDir: $mariaDbCompiledDir"
    echo "mariaDbPackagePath: $mariaDbPackagePath"
    echo "mariaDbVerifiedDir: $mariaDbVerifiedDir"

    echo '############################## Installing the latest SDK for the minimum macOS version to support'
    installMacOsSdk \
        $macOsMinVerToSupport \
        $macOsSdkDir \
        $gitHubCredentials
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi

    echo '############################## Installing the latest stable version of OpenSSL for this version of MariaDB'
    installOpenSsl \
        $workingDir \
        $mariaDbSeries \
        $macOsMinVerToSupport \
        $macOsSdkDir \
        $openSslSourceDir \
        $openSslCompiledDir \
        $gitHubCredentials
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
        $apiRepoBaseUrl \
        $gitHubCredentials
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi
}

function getRepoDir {
    local scriptDir=$(dirname "${BASH_SOURCE[0]}")

    local repoDir="$scriptDir"
    while [ $(ls -Ald "$repoDir/.git" 2>/dev/null | wc -l) -eq 0 ]; do
        repoDir="$repoDir/.."
    done
    pushd $repoDir >/dev/null
    repoDir=$(pwd)
    popd >/dev/null
    echo "$repoDir"
}

function getRootDir {
    local repoDir=${1}
    if [ "$#" -ne 1 ]; then echo 'Illegal number of arguments'; return 1; fi

    pushd $repoDir/.. >/dev/null
    local rootDir=$(pwd)
    popd >/dev/null
    echo "$rootDir"
}

function getApiRepoBaseUrl {
    local repoDir=${1}
    if [ "$#" -ne 1 ]; then echo 'Illegal number of arguments'; return 1; fi

    pushd $repoDir >/dev/null
    # https://api.github.com/repos/:owner/:repo
    local apiRepoBaseUrl=$(git remote get-url origin | sed -e 's/github.com/api.github.com\/repos/' -e 's/\.git$//')
    popd >/dev/null
    echo "$apiRepoBaseUrl"
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
            brew tap "$repoToTap" >/dev/null 2>&1
        fi
        formula=$(basename $package)
        if brew list --versions $formula | grep -q $formula; then
            echo "Skipping installation of formula '$formula'"
        else
            echo "Installing formula '$formula'"
            brew install $formula >/dev/null 2>&1
        fi
    done
}

function getMariaDbLatestVersionPerSeries {
    local resultVar=${1}
    local gitHubCredentials=${2}
    if [ "$#" -ne 2 ]; then echo 'Illegal number of arguments'; return 1; fi

    local mariaDbTagsUrl='https://api.github.com/repos/MariaDB/server/git/refs/tags'
    local mariaDbLatestVersionsJqExpr='map(.ref | ltrimstr("refs/tags/"))
        | map(select(. | test("^mariadb-\\d+\\.\\d+\\.\\d+$")) | ltrimstr("mariadb-") | split("."))
        | map({ series: (.[0] + "." + .[1]), major: .[0], minor: .[1], patch: .[2] })
        | group_by(.series)
        | sort_by((.[0].major | tonumber), (.[0].minor | tonumber))
        | map({ series: .[0].series, latestVersion: . | sort_by(-(.patch | tonumber)) | (.[0].series + "." + .[0].patch) })
        | map(.latestVersion)'
    queryApi mariaDbLatestVersions "$gitHubCredentials" "$mariaDbTagsUrl" "$mariaDbLatestVersionsJqExpr"
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi
    mariaDbLatestVersions=$(echo $mariaDbLatestVersions | tr -d '\n| ')

    eval $resultVar="'$mariaDbLatestVersions'"
}

function getMariaDbLatestBinaryDistributionPerSeries {
    local resultVar=${1}
    local apiRepoBaseUrl=${2}
    local gitHubCredentials=${3}
    if [ "$#" -ne 3 ]; then echo 'Illegal number of arguments'; return 1; fi

    local releasesUrl="$apiRepoBaseUrl/releases"
    local latestDistributionsJqExpr='map({ assets: (.assets // [] | map(.name)), version: .tag_name | ltrimstr("v")})
        | map(select(.assets | map(select(. | test("\\.tar\\.gz$"))) | has(0)) | .version | split("."))
        | map({ series: (.[0] + "." + .[1]), major: .[0], minor: .[1], patch: .[2] })
        | group_by(.series)
        | sort_by((.[0].major | tonumber), (.[0].minor | tonumber))
        | map({ series: .[0].series, latestVersion: . | sort_by(-(.patch | tonumber)) | (.[0].series + "." + .[0].patch) })
        | map(.latestVersion)'
    queryApi latestDistributions "$gitHubCredentials" "$releasesUrl" "$latestDistributionsJqExpr"
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi
    latestDistributions=$(echo $latestDistributions | tr -d '\n| ')

    eval $resultVar="'$latestDistributions'"
}

function getMariaDbBinaryDistributionsToRelease {
    local resultVar=${1}
    local mariaDbLatestVersionPerSeries=${2}
    local mariaDbLatestDistributionPerSeries=${3}
    local overwrite=${4}
    if [ "$#" -ne 4 ]; then echo 'Illegal number of arguments'; return 1; fi

    if [ $overwrite -eq 1 ]; then
        local distributionsToRelease=$mariaDbLatestVersionPerSeries
    else
        local distributionsToRelease=$(echo "$mariaDbLatestVersionPerSeries" | jq -r ". - $mariaDbLatestDistributionPerSeries")
    fi
    distributionsToRelease=$(echo $distributionsToRelease | tr -d '\n| ')

    eval $resultVar="'$distributionsToRelease'"
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
    local mariaDbLatestVersionPerSeries=${2}
    local force=${3}
    if [ "$#" -ne 3 ]; then echo 'Illegal number of arguments'; return 1; fi

    if echo "$mariaDbLatestVersionPerSeries" | jq -r '.[]' | grep -q "$mariaDbVersion"; then
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
    local mariaDbVersion=${1}
    local mariaDbDistributionsToRelease=${2}
    local overwrite=${3}
    if [ "$#" -ne 3 ]; then echo 'Illegal number of arguments'; return 1; fi

    if echo "$mariaDbDistributionsToRelease" | jq -r '.[]' | grep -q "$mariaDbVersion"; then
        Write-Information "A binary distribution for MariaDB $MariaDbVersion has never been released"
        Write-Information 'Proceeding with the build (no cleanup needed)'
        return 0
    fi

    echo "A binary distribution for MariaDB $mariaDbVersion has already been released"
    if [ $overwrite -eq 1 ]; then
        echo 'Proceeding with the build (overwrite flag set)'
        return 0
    fi

    echo 'Stopping the build'
    return 1
}

function installMacOsSdk {
    local macOsMinVerToSupport=${1}
    local macOsSdkDir=${2}
    local gitHubCredentials=${3}
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
    local macOsMinVerToSupport=${3}
    local macOsSdkDir=${4}
    local openSslSourceDir=${5}
    local openSslCompiledDir=${6}
    local gitHubCredentials=${7}
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

    echo '########## Preparing for compilation'
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
    local makeLog=$workingDir/openssl-make-log.txt
    make >$makeLog 2>&1
    local returnValue=$?
    stopShowingProgress $workingDir
    if [ $returnValue -ne 0 ]; then cat $makeLog; popd >/dev/null; return $returnValue; fi

    echo '########## Testing'
    startShowingProgress $workingDir
    local testLog=$workingDir/openssl-test-log.txt
    make test >$testLog 2>&1
    local returnValue=$?
    stopShowingProgress $workingDir
    if [ $returnValue -ne 0 ]; then cat $testLog; popd >/dev/null; return $returnValue; fi
    cat $testLog | grep 'OpenSSL 1.0\|Result'

    echo '########## Installing'
    startShowingProgress $workingDir
    local installLog=$workingDir/openssl-install-log.txt
    make install >$installLog 2>&1
    local returnValue=$?
    stopShowingProgress $workingDir
    if [ $returnValue -ne 0 ]; then cat $installLog; popd >/dev/null; return $returnValue; fi

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
    local makeLog=$workingDir/mariadb-make-log.txt
    LC_ALL=C make >$makeLog 2>&1
    local returnValue=$?
    stopShowingProgress $workingDir
    if [ $returnValue -ne 0 ]; then cat $makeLog; popd >/dev/null; return $returnValue; fi

    echo '########## Testing'
    local returnValue=0
    startShowingProgress $workingDir
    local testLog=$workingDir/mariadb-test-log.txt
    if [ "$mariaDbSeries" == '5.1' ] || [ "$mariaDbSeries" == '5.2' ] || [ "$mariaDbSeries" == '5.3' ]; then
        pushd $mariaDbSourceDir/mysql-test >/dev/null
        if ! ./mysql-test-run.pl --force --parallel=8 --skip-rpl >$testLog 2>&1; then returnValue=1; fi
        popd >/dev/null
    else
        make test >$testLog 2>&1
        returnValue=$?
    fi
    stopShowingProgress $workingDir
    if [ $returnValue -eq 0 ]; then
        cat $testLog | grep 'failed out of\|were successful'
    else
        cat $testLog
    fi

    echo '########## Installing'
    startShowingProgress $workingDir
    local installLog=$workingDir/mariadb-install-log.txt
    make install >$installLog 2>&1
    local returnValue=$?
    stopShowingProgress $workingDir
    if [ $returnValue -ne 0 ]; then cat $installLog; popd >/dev/null; return $returnValue; fi

    echo '########## Packaging binaries'
    mkdir -p $(dirname $mariaDbPackagePath)
    tar -C $mariaDbCompiledDir -zchf $mariaDbPackagePath .

    echo '########## Verifying binaries'
    mkdir -p $mariaDbVerifiedDir
    tar -C $mariaDbVerifiedDir -zxf $mariaDbPackagePath
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
    local apiRepoBaseUrl=${3}
    local gitHubCredentials=${4}
    if [ "$#" -ne 4 ]; then echo 'Illegal number of arguments'; return 1; fi

    local tag="v$mariaDbVersion"

    echo '########## Deleting the release if already existent'
    local releaseForTagUrl="$apiRepoBaseUrl/releases/tags/$tag"
    local releaseIdForTagJqExpr='.id // "missingRelease"'
    queryApi releaseIdForTag "$gitHubCredentials" "$releaseForTagUrl" "$releaseIdForTagJqExpr"
    local returnValue=$?; if [ $returnValue -ne 0 ]; then return $returnValue; fi
    if [ "$releaseIdForTag" == 'missingRelease' ]; then
        echo "No release to delete for tag '$tag'"
    else
        local deleteReleaseUrl="$apiRepoBaseUrl/releases/$releaseIdForTag"
        local response=$(curl -s -S -L -i -X DELETE -u "$gitHubCredentials" "$deleteReleaseUrl" 2>&1)
        if ! echo "$response" | grep -iq '204 No Content'; then
            printf "Unable to delete release '$releaseIdForTag'\n\n$response\n"
            return 1
        fi
        echo "Deleted release '$releaseIdForTag'"

        local deleteTagUrl="$apiRepoBaseUrl/git/refs/tags/$tag"
        local response=$(curl -s -S -L -i -X DELETE -u "$gitHubCredentials" "$deleteTagUrl" 2>&1)
        if ! echo "$response" | grep -iq '204 No Content'; then
            printf "Unable to delete tag '$tag'\n\n$response\n"
            return 1
        fi
        echo "Deleted tag '$tag'"
    fi

    echo '########## Creating the release'
    local createReleaseUrl="$apiRepoBaseUrl/releases"
    local releaseDescription="MariaDB $mariaDbVersion binary distribution"
    local createReleaseBody="{ \"name\": \"$mariaDbVersion\", \"tag_name\": \"$tag\", \"body\": \"$releaseDescription\" }"
    local response=$(curl -s -S -L -i -X POST \
        -H 'Content-Type: application/json' \
        --data "$createReleaseBody" \
        -u "$gitHubCredentials" \
        "$createReleaseUrl" \
        2>&1)
    if ! echo "$response" | grep -iq '201 Created'; then
        printf "Unable to create the release\n\n$response\n"
        return 1
    fi
    local uploadUrl=$(echo "$response" | grep 'upload_url' | awk '{ print $2 }' | tr -d ',' | jq -r 'split("{")[0]')
    echo "Upload URL: '$uploadUrl'"

    echo '########## Retrieving binary archive info'
    local name=$(basename $mariaDbPackagePath)
    local size=$(du -h $mariaDbPackagePath | awk '{ print $1 }' | sed -E 's/^([0-9]+)(M|G)$/\1 \2iB/')
    local md5Checksum=$(md5 -r $mariaDbPackagePath | awk '{ print $1 }' | tee "$mariaDbPackagePath.md5")
    local sha1Checksum=$(shasum -a 1 $mariaDbPackagePath | awk '{ print $1 }' | tee "$mariaDbPackagePath.sha1")
    local sha256Checksum=$(shasum -a 256 $mariaDbPackagePath | awk '{ print $1 }' | tee "$mariaDbPackagePath.sha256")
    local sha512Checksum=$(shasum -a 512 $mariaDbPackagePath | awk '{ print $1 }' | tee "$mariaDbPackagePath.sha512")
    echo "Name: $name"
    echo "Size: $size"
    echo "MD5: $md5Checksum"
    echo "SHA1: $sha1Checksum"
    echo "SHA256: $sha256Checksum"
    echo "SHA512: $sha512Checksum"

    echo '########## Uploading binary archive'
    local uploadAssetUrl="$uploadUrl?name=$name"
    local response=$(curl -s -S -L -i -X POST \
        -H 'Content-Type: application/gzip' \
        -T "$mariaDbPackagePath" \
        -u "$gitHubCredentials" \
        "$uploadAssetUrl" \
        2>&1)
    if ! echo "$response" | grep -iq '201 Created'; then
        printf "Unable to upload the file '$mariaDbPackagePath'\n\n$response\n"
        return 1
    fi

    echo '########## Uploading checksum files'
    for file in $mariaDbPackagePath.*; do
        local uploadAssetUrl="$uploadUrl?name=$(basename $file)"
        local response=$(curl -s -S -L -i -X POST \
            -H 'Content-Type: text/plain' \
            -T "$file" \
            -u "$gitHubCredentials" \
            "$uploadAssetUrl" \
            2>&1)
        if ! echo "$response" | grep -iq '201 Created'; then
            printf "Unable to upload the file '$file'\n\n$response\n"
            return 1
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
    local uri=${3}
    local jqExpression=${4}
    if [ "$#" -ne 4 ]; then echo 'Illegal number of arguments'; return 1; fi

    local onelineJqExpression=$(echo $jqExpression | tr -d '\n' | sed -E 's/  //g')

    local curlResult=0 # declaration and assignment split to prevent $? from being always 0
    curlResult=$(curl -s -S -L -X GET -u "$credentials" "$uri" 2>&1)
    if [ $? -ne 0 ]; then
        echo "Unable to query '$uri' and parse response with the jq expression '$onelineJqExpression'"
        echo "curlResult: $curlResult"
        return 1
    fi

    local jqResult=0 # declaration and assignment split to prevent $? from being always 0
    jqResult=$(echo $curlResult | jq -r "$jqExpression" 2>&1)
    if [ $? -ne 0 ] || [ "$jqResult" == 'null' ]; then
        echo "Unable to query '$uri' and parse response with the jq expression '$onelineJqExpression'"
        echo "curlResult: $curlResult"
        echo "jqResult: $jqResult"
        return 1
    fi

    eval $resultVar="'$jqResult'"
}