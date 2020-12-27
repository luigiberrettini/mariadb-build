function New-MariaDbBinaryDistribution {
    param (
        $MariaDbVersion,
        $MariaDbSeries,
        $OsArchitectureBits,
        $GitHubCredentials,
        $VisualStudioDir,
        [Switch]
        $Force,
        [Switch]
        $Overwrite
    )
    if ($MariaDbVersion -eq $null -or
        $MariaDbSeries -eq $null -or
        $OsArchitectureBits -eq $null -or
        $GitHubCredentials -eq $null -or
        $VisualStudioDir -eq $null) {
        Throw 'Illegal number of arguments'
    }

    $InformationPreference = 'Continue'

    Write-Information '############################## Initializing'
    $repoDir = Get-RepoDir
    Write-Information "repoDir: $repoDir"
    $workingDir = Join-Path (Get-RootDir $repoDir) 'work'
    New-Item -Type Directory -Path $workingDir -ErrorAction Continue | Out-Null
    Write-Information "workingDir: $workingDir"
    $apiRepoBaseUrl = Get-ApiRepoBaseUrl $repoDir
    Write-Information "apiRepoBaseUrl: $apiRepoBaseUrl"

    Write-Information '############################## Installing basic package dependencies'
    Install-PackageDependencies jq

    Write-Information '############################## Determining the latest version for each MariaDB series'
    $mariaDbLatestVersionPerSeries = Get-MariaDbLatestVersionPerSeries $GitHubCredentials
    Write-Information $mariaDbLatestVersionPerSeries

    Write-Information '############################## Determining the latest binary distribution released for each MariaDB series'
    $mariaDbLatestDistributionPerSeries = Get-MariaDbLatestBinaryDistributionPerSeries `
        $mariaDbLatestVersionPerSeries `
        $OsArchitectureBits `
        $apiRepoBaseUrl `
        $GitHubCredentials
    Write-Information $mariaDbLatestDistributionPerSeries

    Write-Information '############################## Determining the binary distributions to be released'
    $mariaDbDistributionsToRelease = Get-MariaDbBinaryDistributionsToRelease `
        $mariaDbLatestVersionPerSeries `
        $mariaDbLatestDistributionPerSeries `
        $Overwrite
    Write-Information $mariaDbDistributionsToRelease

    Write-Information '############################## Determining MariaDB version and series'
    $MariaDbVersion = Get-MariaDbVersion $mariaDbLatestVersionPerSeries $MariaDbVersion $MariaDbSeries
    $MariaDbSeries = Get-MariaDbSeries $MariaDbVersion
    Write-Information "MariaDB $MariaDbVersion ($MariaDbSeries series)"

    Write-Information '############################## Checking if a MariaDB build was requested for the latest version of the series'
    Assert-MostRecentMariaDbVersion `
        $MariaDbVersion `
        $mariaDbLatestVersionPerSeries `
        $Force

    Write-Information '############################## Checking if the MariaDB version has no released binary distribution'
    Assert-NotReleasedBinaryDistribution `
        $MariaDbVersion `
        $mariaDbDistributionsToRelease `
        $Overwrite

    Write-Information '############################## Installing build related dependencies'
    Install-PackageDependencies `
        7zip.install `
        cmake.install `
        strawberryperl
    if ($MariaDbSeries -eq '5.1' -or $MariaDbSeries -eq '5.2' -or $MariaDbSeries -eq '5.3') {
        # Visual C++ 2008 Express (lacks x64 compilers)
        #Install-PackageDependencies nsis visualcplusplusexpress2008 vcredist2008
        # Visual C++ 2010 Express (lacks x64 compilers)
        #Install-PackageDependencies nsis vcexpress2010 vcredist2010
        # Visual Studio 2012 Professional
        Install-PackageDependencies nsis visualstudio2012professional
    }
    else {
        Install-PackageDependencies ruby visualstudio2017buildtools
    }
    Install-GnuSoftware `
        'https://vorboss.dl.sourceforge.net/project/gnuwin32/bison/2.4.1/bison-2.4.1-setup.exe' `
        $WorkingDir `
        'bison'
    Install-GnuSoftware `
        'https://vorboss.dl.sourceforge.net/project/gnuwin32/diffutils/2.8.7-1/diffutils-2.8.7-1.exe' `
        $WorkingDir `
        'diff'

    Write-Information '############################## Preparing for execution'
    $mariaDbSourceDir = "$workingDir\mariadb$OsArchitectureBits\$MariaDbVersion\src"
    $mariaDbBuildDir = "$workingDir\mariadb$OsArchitectureBits\$MariaDbVersion\build"
    $mariaDbCompiledDir = "$workingDir\mariadb$OsArchitectureBits\$MariaDbVersion\compiled"
    $mariaDbPackageName = "mariadb-$MariaDbVersion-win$OsArchitectureBits"
    $mariaDbPackagePath = "$workingDir\mariadb$OsArchitectureBits\$MariaDbVersion\packaged\$mariaDbPackageName.zip"
    $mariaDbVerifiedDir = "$workingDir\mariadb$OsArchitectureBits\$MariaDbVersion\verified"
    Write-Information "mariaDbSourceDir: $mariaDbSourceDir"
    Write-Information "mariaDbBuildDir: $mariaDbBuildDir"
    Write-Information "mariaDbCompiledDir: $mariaDbCompiledDir"
    Write-Information "mariaDbPackagePath: $mariaDbPackagePath"
    Write-Information "mariaDbVerifiedDir: $mariaDbVerifiedDir"

    Write-Information '############################## Building MariaDB from sources'
    Build-MariaDb `
        $workingDir `
        $MariaDbVersion `
        $MariaDbSeries `
        $OsArchitectureBits `
        $mariaDbSourceDir `
        $mariaDbBuildDir `
        $mariaDbCompiledDir `
        $mariaDbPackagePath `
        $mariaDbVerifiedDir

    Write-Information '############################## Publishing MariaDB binaries'
    Publish-MariaDbBinaries `
        $MariaDbVersion `
        $mariaDbPackagePath `
        $apiRepoBaseUrl `
        $GitHubCredentials
}

function Get-RepoDir {
    $repoDir = $PSScriptRoot
    while ($(Get-ChildItem -Path $repoDir -Filter '.git' -Force | Measure-Object).Count -eq 0) {
        $repoDir = (Get-Item (Join-Path $repoDir '..')).FullName
    }
    return $repoDir
}

function Get-RootDir {
    param (
        $RepoDir
    )
    if ($PSBoundParameters.Count -ne 1) { Throw 'Illegal number of arguments' }

    return (Get-Item (Join-Path $repoDir '..')).FullName
}

function Get-ApiRepoBaseUrl {
    param (
        $RepoDir
    )
    if ($PSBoundParameters.Count -ne 1) { Throw 'Illegal number of arguments' }

    $gitPath = Get-CommandPath -Name 'git'
    $gitArgs = @('-C', "$RepoDir", 'remote', 'get-url', 'origin')
    $originUrl = & $gitPath $gitArgs

    # https://api.github.com/repos/:owner/:repo
    return $originUrl -Replace 'github.com', 'api.github.com/repos' -Replace '\.git$', ''
}

function Install-PackageDependencies {
    $chocoPath = Get-CommandPath -Name 'choco'
    for ($i = 0; $i -lt $args.count; $i++) {
        $package = $args[$i]
        $chocoArgs = @('list', "$package", '--limit-output', '--local-only', '--id-only', '--exact')
        $foundPackage = & $chocoPath $chocoArgs
        if ($foundPackage -eq $package) {
            Write-Information "Skipping installation of package '$package'"
            continue
        }
        Write-Information "Installing package '$package'"
        $chocoArgs = @('install', "$package", '--limit-output', '--no-progress', '--confirm')
        & $chocoPath $chocoArgs | Out-Null
    }
}

function Get-MariaDbLatestVersionPerSeries {
    param (
        $GitHubCredentials
    )
    if ($PSBoundParameters.Count -ne 1) { Throw 'Illegal number of arguments' }

    $mariaDbTagsUrl = 'https://api.github.com/repos/MariaDB/server/git/refs/tags'
    $mariaDbLatestVersionsJqExpr = 'map(.ref | ltrimstr(\"refs/tags/\"))
        | map(select(. | test(\"^mariadb-\\d+\\.\\d+\\.\\d+$\")) | ltrimstr(\"mariadb-\") | split(\".\"))
        | map({ series: (.[0] + \".\" + .[1]), major: .[0], minor: .[1], patch: .[2] })
        | group_by(.series)
        | sort_by((.[0].major | tonumber), (.[0].minor | tonumber))
        | map({ series: .[0].series, latestVersion: . | sort_by(-(.patch | tonumber)) | (.[0].series + \".\" + .[0].patch) })
        | map(.latestVersion)'
    $mariaDbLatestVersions = Invoke-ApiRequest $GitHubCredentials $mariaDbTagsUrl $mariaDbLatestVersionsJqExpr

    return $mariaDbLatestVersions -Replace '\s', '' -join ''
}

function Get-MariaDbLatestBinaryDistributionPerSeries {
    param (
        $MariaDbLatestVersionPerSeries,
        $OsArchitectureBits,
        $ApiRepoBaseUrl,
        $GitHubCredentials
    )
    if ($PSBoundParameters.Count -ne 4) { Throw 'Illegal number of arguments' }

    $officialVersions = $MariaDbLatestVersionPerSeries |
        jq -r '.[]' |
        Where-Object {
            $version = $_
            $windows = if ($OsArchitectureBits -eq 32) { 'win32' } else { 'winx64' }
            $uri = "https://downloads.mariadb.com/MariaDB/mariadb-${version}/${windows}-packages/mariadb-${version}-${windows}.zip"
            $statusCode = 0
            try {
                $response = Invoke-WebRequest -Method Head -Uri $uri
                return $response.StatusCode -eq 200
            }
            catch {
                return $_.Exception.Response.StatusCode.Value__ -eq 200
            }
        }

    $releasesUrl = "$ApiRepoBaseUrl/releases"
    $latestReleasesJqExpr = "map({ assets: (.assets // [] | map(.name)), version: .tag_name | ltrimstr(\""v\"")})
        | map(select(.assets | map(select(. | test(\""$OsArchitectureBits\\.zip$\""))) | has(0)) | .version)
        | .[]"
    $latestReleases = Invoke-ApiRequest $GitHubCredentials $releasesUrl $latestReleasesJqExpr

    $latestDistributions = "[" + (($officialVersions + $latestReleases | ForEach-Object { """$_""" }) -join ',') + "]"
    $sortJqExpr = 'map(split(\".\"))
        | map({ series: (.[0] + \".\" + .[1]), major: .[0], minor: .[1], patch: .[2] })
        | group_by(.series)
        | sort_by((.[0].major | tonumber), (.[0].minor | tonumber))
        | map({ series: .[0].series, latestVersion: . | sort_by(-(.patch | tonumber)) | (.[0].series + \".\" + .[0].patch) })
        | map(.latestVersion)'
    $oneLineSortJqExpr = $sortJqExpr -Replace '\s{2,}', ' '
    $sortedLatestDistributions = ($latestDistributions | jq -r $oneLineSortJqExpr)

    return $sortedLatestDistributions -Replace '\s', '' -join ''
}

function Get-MariaDbBinaryDistributionsToRelease {
    param (
        $mariaDbLatestVersionPerSeries,
        $mariaDbLatestDistributionPerSeries,
        $Overwrite
    )
    if ($PSBoundParameters.Count -ne 3) { Throw 'Illegal number of arguments' }

    if ($Overwrite) {
        return $mariaDbLatestVersionPerSeries
    }

    $mariaDbLatestDistributionPerSeries = $mariaDbLatestDistributionPerSeries -Replace '"', '\"'
    $distributionsToRelease = $mariaDbLatestVersionPerSeries | jq ". - $mariaDbLatestDistributionPerSeries"

    return $distributionsToRelease -Replace '\s', '' -join ''
}

function Get-MariaDbVersion {
    param (
        $MariaDbLatestVersionPerSeries,
        $MariaDbVersion,
        $MariaDbSeries
    )
    if ($MariaDbLatestVersionPerSeries -eq $null -or $MariaDbVersion -eq $null) { Throw 'Illegal arguments' }

    if ($MariaDbVersion -eq 'latest') {
        if ($PSBoundParameters.Count -ne 3) { Throw 'Illegal number of arguments' }
        return $MariaDbLatestVersionPerSeries | jq -r '.[]' | Where-Object { $_.StartsWith($MariaDbSeries) }
    }
    return $MariaDbVersion
}

function Get-MariaDbSeries {
    param (
        $MariaDbVersion
    )
    if ($PSBoundParameters.Count -ne 1) { Throw 'Illegal number of arguments' }

    return $MariaDbVersion -Replace '^([0-9]+\.[0-9]+)\.[0-9]+$', '$1'
}

function Assert-MostRecentMariaDbVersion {
    param (
        $MariaDbVersion,
        $MariaDbLatestVersionPerSeries,
        $Force
    )
    if ($PSBoundParameters.Count -ne 3) { Throw 'Illegal number of arguments' }

    if ($MariaDbLatestVersionPerSeries | jq -r '.[]' | Where-Object { $_ -eq $MariaDbVersion }) {
        Write-Information "MariaDB $MariaDbVersion is the most recent version of the series"
        Write-Information 'Proceeding with the build'
        return
    }

    Write-Information "MariaDB $MariaDbVersion is not the most recent version of the series"
    if ($Force) {
        Write-Information 'Proceeding with the build (force flag set)'
        return
    }

    Write-Information 'Stopping the build'
    Throw
}

function Assert-NotReleasedBinaryDistribution {
    param (
        $MariaDbVersion,
        $MariaDbDistributionsToRelease,
        $Overwrite
    )
    if ($PSBoundParameters.Count -ne 3) { Throw 'Illegal number of arguments' }

    if ($MariaDbDistributionsToRelease | jq -r '.[]' | Where-Object { $_ -eq $MariaDbVersion }) {
        Write-Information "A binary distribution for MariaDB $MariaDbVersion has never been released"
        Write-Information 'Proceeding with the build (no cleanup needed)'
        return
    }

    Write-Information "A binary distribution for MariaDB $MariaDbVersion has already been released"
    if ($Overwrite) {
        Write-Information 'Proceeding with the build (overwrite flag set)'
        return
    }

    Write-Information 'Stopping the build'
    Throw
}

function Install-GnuSoftware {
    param (
        $installerUrl,
        $WorkingDir,
        $SwName
    )
    if ($PSBoundParameters.Count -ne 3) { Throw 'Illegal number of arguments' }

    Write-Information "Installing '$SwName'"

    $installerPath = "$WorkingDir\${SwName}inst.exe"
    $installerArgs = @(
        '/SP-',
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        "/LOG=""$WorkingDir\$SwName-log.txt""",
        '/NORESTART',
        "/DIR=""$WorkingDir\$SwName""",
        '/NOICONS'
    )

    Invoke-WebRequest -Method Get -Uri $installerUrl -OutFile $installerPath
    if (-not $?) { Throw }

    & $installerPath $installerArgs
    if (-not $?) { Get-Content -Path "$WorkingDir\$SwName-log.txt"; Throw }

    $env:Path = "$WorkingDir\$SwName\bin;$env:Path"
}

function Build-MariaDb {
    param (
        $WorkingDir,
        $MariaDbVersion,
        $MariaDbSeries,
        $OsArchitectureBits,
        $MariaDbSourceDir,
        $MariaDbBuildDir,
        $MariaDbCompiledDir,
        $MariaDbPackagePath,
        $MariaDbVerifiedDir
    )
    if ($PSBoundParameters.Count -ne 9) { Throw 'Illegal number of arguments' }

    Write-Information '########## Downloading and extracting'
    $mariaDbUrl = "https://downloads.mariadb.com/MariaDB/mariadb-${MariaDbVersion}/source/mariadb-${MariaDbVersion}.tar.gz"
    New-Item -Type Directory -Path $MariaDbSourceDir -ErrorAction Continue | Out-Null
    $mariaDbArchive = "$WorkingDir\mariadb.tar.gz"
    Invoke-WebRequest -Method Get -Uri $mariaDbUrl -OutFile $mariaDbArchive
    if (-not $?) { Throw }
    $7zPath = Get-CommandPath -Name '7z'
    $7zArgs = @('x', '-bd', '-bb0', '-tgzip', "-o$WorkingDir", $mariaDbArchive)
    & $7zPath $7zArgs | Out-Null
    if (-not $?) { Throw }
    $tmpDir = "$WorkingDir\tmp"
    New-Item -Type Directory -Path $tmpDir -ErrorAction Continue | Out-Null
    $7zArgs = @('x', '-aoa', '-bd', '-bb0', '-ttar', "-o$tmpDir", ($mariaDbArchive -Replace '\.gz', ''))
    & $7zPath $7zArgs | Out-Null
    if (-not $?) { Throw }
    Move-Item -Path "$tmpDir\*\*" -Destination $MariaDbSourceDir
    Remove-Item -Path $tmpDir -Recurse
    if (Test-Path -Path $MariaDbSourceDir\storage\mroonga\vendor\groonga\vendor\download_lz4.rb) {
        Push-Location $MariaDbSourceDir\storage\mroonga\vendor\groonga\vendor
        $rubyPath = Get-CommandPath -Name 'ruby'
        $rubyArgs = @('.\download_lz4.rb')
        & $rubyPath $rubyArgs | Out-Null
        Pop-Location
    }

    New-Item -Type Directory -Path $MariaDbBuildDir -ErrorAction Continue | Out-Null
    if ($MariaDbSeries -eq '5.1' -or $MariaDbSeries -eq '5.2' -or $MariaDbSeries -eq '5.3') {
        Push-Location $MariaDbSourceDir
    }
    else {
        Push-Location $MariaDbBuildDir
    }

    Write-Information '########## Preparing for compilation'
    New-Item -Type Directory -Path $MariaDbCompiledDir -ErrorAction Continue | Out-Null
    if ($MariaDbSeries -eq '5.1' -or $MariaDbSeries -eq '5.2' -or $MariaDbSeries -eq '5.3') {
        $cscriptPath = Get-CommandPath -Name 'cscript'
        $cscriptArgs = @('.\win\configure.js', '/nologo', '/b')
        & $cscriptPath $cscriptArgs | Out-Null
        if (-not $?) { Pop-Location; Throw }
    }
    $cmakePath = Get-CommandPath -Name 'cmake'
    $cmakePath = Get-CommandPath -Name 'cmake'
    # Visual Studio 2008
    #$visualStudioArg = if ($OsArchitectureBits -eq 32) { 'Visual Studio 9 2008' } else { 'Visual Studio 9 2008 Win64' }
    # Visual Studio 2010
    #$visualStudioArg = if ($OsArchitectureBits -eq 32) { 'Visual Studio 10 2010' } else { 'Visual Studio 10 2010 Win64' }
    # Visual Studio 2012
    $visualStudioArg = if ($OsArchitectureBits -eq 32) { 'Visual Studio 11 2012' } else { 'Visual Studio 11 2012 Win64' }
    $cmakeArgs = @(
        "$MariaDbSourceDir",
        '-G',
        $visualStudioArg,
        '-DCMAKE_SKIP_RPATH=YES',
        "-DCMAKE_INSTALL_PREFIX=$MariaDbCompiledDir",
        '-Wno-dev'
    )
    & $cmakePath $cmakeArgs | Out-Null
    if (-not $?) { Pop-Location; Throw }

    Write-Information '########## Compiling'
    $cmakePath = Get-CommandPath -Name 'cmake'
    $targetArg = if ($MariaDbSeries -eq '5.1' -or $MariaDbSeries -eq '5.2' -or $MariaDbSeries -eq '5.3') { 'package' } else { 'win_package' }
    $cmakeArgs = @('--build', '.', '--config', 'RelWithDebInfo', '--target', $targetArg)
    $makeLog = "$WorkingDir\mariadb-make-log.txt"
    Invoke-CommandWithProgress -ScriptBlock {
        param ($cmake, $arguments, $logFile)
        & $cmake $arguments 2>&1 | Out-File -FilePath $logFile
    } -ArgumentList $cmakePath, $cmakeArgs, $makeLog
    if (-not $?) { Get-Content -Path $makeLog; Pop-Location; Throw }
    (Get-Content -Path $makeLog | Select-String -Pattern '========== Build') -Replace '\n', ''

    Write-Information '########## Testing'
    Push-Location "$MariaDbSourceDir\mysql-test"
    $filePath = '.\mysql-test-run.pl'
    $pattern = 'if \( not defined \@\$completed \) \{'
    $replacement = 'if ( not @$completed ) {'
    ((Get-Content -Path $filePath) -Replace $pattern, $replacement) | Set-Content -Path $filePath
    $pattern = "return defined \`$maria_var and \`$maria_var eq 'TRUE';"
    $replacement = "return (defined `$maria_var and `$maria_var eq 'TRUE');"
    ((Get-Content -Path $filePath) -Replace $pattern, $replacement) | Set-Content -Path $filePath
    $pattern = '# This is the current version, just continue'
    $replacement = 'push @INC, ".";'
    ((Get-Content -Path $filePath) -Replace $pattern, $replacement) | Set-Content -Path $filePath
    $returnValue = $false
    $perlPath = Get-CommandPath -Name 'perl'
    $perlArgs = @($filePath, '--force', '--parallel=8', '--skip-rpl')
    $testLog = "$WorkingDir\mariadb-test-log.txt"
    Invoke-CommandWithProgress -ScriptBlock {
        param ($perl, $arguments, $logFile)
        if (& $perl $arguments 2>&1 | Out-File -FilePath $logFile) {
           Get-Content -Path $logFile | Select-String -Pattern 'failed out of\|were successful' | Set-Content -Path $logFile
        }
    } -ArgumentList $perlPath, $perlArgs, $testLog
    Get-Content -Path $testLog
    Pop-Location

    Write-Information '########## Packaging binaries'
    $tmpDir = "$WorkingDir\tmp"
    $packageRootDirName = "mariadb-$env:mariaDbVersion-win$(if ($OsArchitectureBits -eq 32) { '32' } else { 'x64' })"
    $toPackageDir = "$tmpDir\$packageRootDirName"
    New-Item -Type Directory -Path $toPackageDir -ErrorAction Continue | Out-Null
    if ($MariaDbSeries -eq '5.1') {
        Copy-MariaDbBinaries $MariaDbSourceDir $toPackageDir
    }
    else {
        Copy-Item -Path "$MariaDbCompiledDir\*" -Destination "$toPackageDir" -Recurse
    }
    if ((Get-ChildItem -Path $toPackageDir | Measure-Object).Count -eq 0) { Pop-Location; Throw }
    New-Item -Type Directory -Path (Split-Path -Parent -Path $MariaDbPackagePath) -ErrorAction Continue | Out-Null
    Compress-Archive -Path $toPackageDir -DestinationPath $MariaDbPackagePath
    if (-not $?) { Pop-Location; Throw }
    Remove-Item -Path $tmpDir -Recurse

    Write-Information '########## Verifying binaries'
    New-Item -Type Directory -Path $MariaDbVerifiedDir -ErrorAction Continue | Out-Null
    $tmpDir = "$WorkingDir\tmp"
    New-Item -Type Directory -Path $tmpDir -ErrorAction Continue | Out-Null
    Expand-Archive -Path $MariaDbPackagePath -DestinationPath $tmpDir
    Move-Item -Path "$tmpDir\*\*" -Destination $MariaDbVerifiedDir
    Remove-Item -Path $tmpDir -Recurse
    if ($MariaDbSeries -eq '5.1') {
        $perlPath = Get-CommandPath -Name 'perl'
        $perlArgs = @(
            "$MariaDbSourceDir\scripts\mysql_install_db.pl",
            '--no-defaults',
            "--basedir=$MariaDbVerifiedDir",
            "--datadir=$MariaDbVerifiedDir\data",
            '--force',
            '--skip-name-resolve'
        )
        & $perlPath $perlArgs
    }
    else {
        $mysqlInstallDbPath = Get-ChildItem -Path $MariaDbVerifiedDir -Depth 2 -Filter 'mysql_install_db.exe' |
            Where-Object { ! $_.PSIsContainer } |
            ForEach-Object { $_.FullName } |
            Select-Object -First 1
        $mysqlInstallDbArgs = @(
            '--no-defaults',
            "--basedir=$MariaDbVerifiedDir",
            "--datadir=$MariaDbVerifiedDir\data",
            '--force',
            '--skip-name-resolve'
        )
        & $mysqlInstallDbPath $mysqlInstallDbArgs
    }
    if (-not $?) { Pop-Location; Throw }

    Pop-Location
}

# PowerShell port of <MariaDB source root folder>\scripts\make_win_bin_dist
function Copy-MariaDbBinaries {
    param (
        $MariaDbSourceDir,
        $Destination
    )
    if ($PSBoundParameters.Count -ne 2) { Throw 'Illegal number of arguments' }

    ### Copy executables and client DLL
    New-Item -Type Directory -Path $Destination\bin -ErrorAction Continue | Out-Null

    Copy-Item -Path client\relwithdebinfo\*.exe -Destination $Destination\bin
    Copy-Item -Path extra\relwithdebinfo\*.exe -Destination $Destination\bin

    $MYISAM_BINARIES = @('myisamchk', 'myisamlog', 'myisampack', 'myisam_ftdump')
    foreach ($eng in $MYISAM_BINARIES) {
        Copy-Item -Path storage\myisam\relwithdebinfo\$eng.exe -Destination $Destination\bin
        Copy-Item -Path storage\myisam\relwithdebinfo\$eng.pdb -Destination $Destination\bin
    }

    $MARIA_BINARIES = @('maria_chk', 'maria_dump_log', 'maria_ftdump', 'maria_pack', 'maria_read_log')
    foreach ($eng in $MARIA_BINARIES) {
        Copy-Item -Path storage\maria\relwithdebinfo\$eng.pdb -Destination $Destination\bin
        Copy-Item -Path storage\maria\relwithdebinfo\$eng.exe -Destination $Destination\bin
    }

    if (Test-Path -Path storage\pbxt\bin\xtstat.exe) {
        Copy-Item -Path storage\pbxt\bin\xtstat.exe -Destination $Destination\bin
        Copy-Item -Path storage\pbxt\bin\xtstat.pdb -Destination $Destination\bin
    }

    Copy-Item -Path server-tools\instance-manager\relwithdebinfo\*.exe -Destination $Destination\bin
    Copy-Item -Path server-tools\instance-manager\relwithdebinfo\*.pdb -Destination $Destination\bin
    Copy-Item -Path client\relwithdebinfo\mysql.pdb -Destination $Destination\bin
    Copy-Item -Path client\relwithdebinfo\mysqladmin.pdb -Destination $Destination\bin
    Copy-Item -Path client\relwithdebinfo\mysqlbinlog.pdb -Destination $Destination\bin
    Copy-Item -Path client\relwithdebinfo\mysqldump.pdb -Destination $Destination\bin
    Copy-Item -Path client\relwithdebinfo\mysqlimport.pdb -Destination $Destination\bin
    Copy-Item -Path client\relwithdebinfo\mysqlshow.pdb -Destination $Destination\bin
    Copy-Item -Path tests\relwithdebinfo\*.exe -Destination $Destination\bin
    Copy-Item -Path libmysql\relwithdebinfo\libmysql.dll -Destination $Destination\bin

    Copy-Item -Path sql\relwithdebinfo\mysqld.exe -Destination $Destination\bin
    Copy-Item -Path sql\relwithdebinfo\mysqld.pdb -Destination $Destination\bin

    if (Test-Path -Path sql\debug\mysqld.exe) {
        Copy-Item -Path sql\debug\mysqld.exe -Destination $Destination\bin\mysqld-debug.exe
        Copy-Item -Path sql\debug\mysqld.pdb -Destination $Destination\bin\mysqld-debug.pdb
    }

    ### Copy data directory, readme files, etc.
    if (Test-Path -Path win\data) {
        Copy-Item -Path win\data -Destination $Destination -Recurse
    }

    New-Item -Type Directory -Path $Destination\Docs -ErrorAction Continue | Out-Null
    Copy-Item -Path Docs\INSTALL-BINARY -Destination $Destination\Docs
    if (Test-Path -Path Docs\manual.chm) { Copy-Item -Path Docs\manual.chm -Destination $Destination\Docs }
    if (Test-Path -Path ChangeLog) { Copy-Item -Path ChangeLog -Destination $Destination\Docs }
    Copy-Item -Path support-files\my-*.ini -Destination $Destination
    Copy-Item -Path README -Destination $Destination

    if (Test-Path -Path COPYING) {
        Copy-Item -Path COPYING -Destination $Destination
        Copy-Item -Path EXCEPTIONS-CLIENT -Destination $Destination
        Copy-Item -Path COPYING -Destination $Destination\Docs
    }

    if ((Test-Path -Path libmysqld\relwithdebinfo\mysqlserver.lib) -and (Test-Path -Path libmysqld\relwithdebinfo\libmysqld.lib)) {
        New-Item -Type Directory -Path $Destination\include -ErrorAction Continue | Out-Null
        Copy-Item -Path libmysqld\libmysqld.def -Destination $Destination\include

        New-Item -Type Directory -Path $Destination\Embedded\static\release -ErrorAction Continue | Out-Null
        Copy-Item -Path libmysqld\relwithdebinfo\mysqlserver.lib -Destination $Destination\Embedded\static\release
        Copy-Item -Path libmysqld\relwithdebinfo\mysqlserver.pdb -Destination $Destination\Embedded\static\release

        New-Item -Type Directory -Path $Destination\Embedded\DLL\release -ErrorAction Continue | Out-Null
        Copy-Item -Path libmysqld\relwithdebinfo\libmysqld.dll -Destination $Destination\Embedded\DLL\release
        Copy-Item -Path libmysqld\relwithdebinfo\libmysqld.exp -Destination $Destination\Embedded\DLL\release
        Copy-Item -Path libmysqld\relwithdebinfo\libmysqld.lib -Destination $Destination\Embedded\DLL\release
        Copy-Item -Path libmysqld\relwithdebinfo\libmysqld.pdb -Destination $Destination\Embedded\DLL\release

        if (Test-Path -Path libmysqld\debug\libmysqld.lib) {
            New-Item -Type Directory -Path $Destination\Embedded\static\debug -ErrorAction Continue | Out-Null
            Copy-Item -Path libmysqld\debug\mysqlserver.lib -Destination $Destination\Embedded\static\debug
            Copy-Item -Path libmysqld\debug\mysqlserver.pdb -Destination $Destination\Embedded\static\debug

            New-Item -Type Directory -Path $Destination\Embedded\DLL\debug -ErrorAction Continue | Out-Null
            Copy-Item -Path libmysqld\debug\libmysqld.dll -Destination $Destination\Embedded\DLL\debug
            Copy-Item -Path libmysqld\debug\libmysqld.exp -Destination $Destination\Embedded\DLL\debug
            Copy-Item -Path libmysqld\debug\libmysqld.lib -Destination $Destination\Embedded\DLL\debug
            Copy-Item -Path libmysqld\debug\libmysqld.pdb -Destination $Destination\Embedded\DLL\debug
        }
    }

    ### Note: Make sure to sync with include\Makefile.am and WiX installer XML specifications
    New-Item -Type Directory -Path $Destination\include -ErrorAction Continue | Out-Null
    Copy-Item -Path include\mysql.h -Destination $Destination\include
    Copy-Item -Path include\mysql_com.h -Destination $Destination\include
    Copy-Item -Path include\mysql_time.h -Destination $Destination\include
    Copy-Item -Path include\my_list.h -Destination $Destination\include
    Copy-Item -Path include\my_alloc.h -Destination $Destination\include
    Copy-Item -Path include\typelib.h -Destination $Destination\include
    Copy-Item -Path include\my_dbug.h -Destination $Destination\include
    Copy-Item -Path include\m_string.h -Destination $Destination\include
    Copy-Item -Path include\my_sys.h -Destination $Destination\include
    Copy-Item -Path include\my_xml.h -Destination $Destination\include
    Copy-Item -Path include\mysql_embed.h -Destination $Destination\include
    Copy-Item -Path include\my_pthread.h -Destination $Destination\include
    Copy-Item -Path include\my_no_pthread.h -Destination $Destination\include
    Copy-Item -Path include\decimal.h -Destination $Destination\include
    Copy-Item -Path include\errmsg.h -Destination $Destination\include
    Copy-Item -Path include\my_global.h -Destination $Destination\include
    Copy-Item -Path include\my_net.h -Destination $Destination\include
    Copy-Item -Path include\my_getopt.h -Destination $Destination\include
    Copy-Item -Path include\sslopt-longopts.h -Destination $Destination\include
    Copy-Item -Path include\my_dir.h -Destination $Destination\include
    Copy-Item -Path include\sslopt-vars.h -Destination $Destination\include
    Copy-Item -Path include\sslopt-case.h -Destination $Destination\include
    Copy-Item -Path include\sql_common.h -Destination $Destination\include
    Copy-Item -Path include\keycache.h -Destination $Destination\include
    Copy-Item -Path include\m_ctype.h -Destination $Destination\include
    Copy-Item -Path include\my_attribute.h -Destination $Destination\include
    Copy-Item -Path include\my_compiler.h -Destination $Destination\include
    Copy-Item -Path include\mysqld_error.h -Destination $Destination\include
    Copy-Item -Path include\sql_state.h -Destination $Destination\include
    Copy-Item -Path include\mysqld_ername.h -Destination $Destination\include
    Copy-Item -Path include\mysql_version.h -Destination $Destination\include
    Copy-Item -Path include\config-win.h -Destination $Destination\include
    Copy-Item -Path libmysql\libmysql.def -Destination $Destination\include

    New-Item -Type Directory -Path $Destination\include\mysql -ErrorAction Continue | Out-Null
    Copy-Item -Path include\mysql\plugin.h -Destination $Destination\include\mysql

    ### Client libraries and other libraries
    New-Item -Type Directory -Path $Destination\lib -ErrorAction Continue | Out-Null
    Copy-Item -Path sql\relwithdebinfo\mysqld.lib -Destination $Destination\lib

    New-Item -Type Directory -Path $Destination\lib\opt -ErrorAction Continue | Out-Null
    Copy-Item -Path libmysql\relwithdebinfo\libmysql.dll -Destination $Destination\lib\opt
    Copy-Item -Path libmysql\relwithdebinfo\libmysql.lib -Destination $Destination\lib\opt
    Copy-Item -Path libmysql\relwithdebinfo\libmysql.pdb -Destination $Destination\lib\opt
    Copy-Item -Path libmysql\relwithdebinfo\mysqlclient.lib -Destination $Destination\lib\opt
    if (Test-Path -Path libmysql\relwithdebinfo\mysqlclient.pdb) {
        Copy-Item -Path libmysql\relwithdebinfo\mysqlclient.pdb -Destination $Destination\lib\opt
    }
    Copy-Item -Path mysys\relwithdebinfo\mysys.lib -Destination $Destination\lib\opt
    if (Test-Path -Path mysys\relwithdebinfo\mysys.pdb) {
        Copy-Item -Path mysys\relwithdebinfo\mysys.pdb -Destination $Destination\lib\opt
    }
    Copy-Item -Path regex\relwithdebinfo\regex.lib -Destination $Destination\lib\opt
    if (Test-Path -Path regex\relwithdebinfo\regex.pdb) {
        Copy-Item -Path regex\relwithdebinfo\regex.pdb -Destination $Destination\lib\opt
    }
    Copy-Item -Path strings\relwithdebinfo\strings.lib -Destination $Destination\lib\opt
    if (Test-Path -Path strings\relwithdebinfo\strings.pdb) {
        Copy-Item -Path strings\relwithdebinfo\strings.pdb -Destination $Destination\lib\opt
    }
    Copy-Item -Path zlib\relwithdebinfo\zlib.lib -Destination $Destination\lib\opt
    if (Test-Path -Path zlib\relwithdebinfo\zlib.pdb) {
        Copy-Item -Path zlib\relwithdebinfo\zlib.pdb -Destination $Destination\lib\opt
    }

    if (Test-Path -Path storage\innodb_plugin) {
        New-Item -Type Directory -Path $Destination\lib\plugin -ErrorAction Continue | Out-Null
        Copy-Item -Path storage\innodb_plugin\relwithdebinfo\ha_innodb_plugin.dll -Destination $Destination\lib\plugin
        Copy-Item -Path storage\innodb_plugin\relwithdebinfo\ha_innodb_plugin.pdb -Destination $Destination\lib\plugin
    }

    if (Test-Path -Path libmysql\debug\libmysql.lib) {
        New-Item -Type Directory -Path $Destination\lib\debug -ErrorAction Continue | Out-Null
        Copy-Item -Path libmysql\debug\libmysql.dll -Destination $Destination\lib\debug
        Copy-Item -Path libmysql\debug\libmysql.lib -Destination $Destination\lib\debug
        Copy-Item -Path libmysql\debug\libmysql.pdb -Destination $Destination\lib\debug
        Copy-Item -Path libmysql\debug\mysqlclient.lib -Destination $Destination\lib\debug
        Copy-Item -Path libmysql\debug\mysqlclient.pdb -Destination $Destination\lib\debug
        Copy-Item -Path mysys\debug\mysys.lib -Destination $Destination\lib\debug
        Copy-Item -Path mysys\debug\mysys.pdb -Destination $Destination\lib\debug
        Copy-Item -Path regex\debug\regex.lib -Destination $Destination\lib\debug
        Copy-Item -Path regex\debug\regex.pdb -Destination $Destination\lib\debug
        Copy-Item -Path strings\debug\strings.lib -Destination $Destination\lib\debug
        Copy-Item -Path strings\debug\strings.pdb -Destination $Destination\lib\debug
        Copy-Item -Path zlib\debug\zlib.lib -Destination $Destination\lib\debug
        Copy-Item -Path zlib\debug\zlib.pdb -Destination $Destination\lib\debug

        if (Test-Path -Path storage\innodb_plugin) {
            New-Item -Type Directory -Path $Destination\lib\plugin\debug -ErrorAction Continue | Out-Null
            Copy-Item -Path storage\innodb_plugin\debug\ha_innodb_plugin.dll -Destination $Destination\lib\plugin\debug
            Copy-Item -Path storage\innodb_plugin\debug\ha_innodb_plugin.lib -Destination $Destination\lib\plugin\debug
            Copy-Item -Path storage\innodb_plugin\debug\ha_innodb_plugin.pdb -Destination $Destination\lib\plugin\debug
        }
    }

    ### Copy the test directory
    New-Item -Type Directory -Path $Destination\mysql-test -ErrorAction Continue | Out-Null
    Copy-Item -Path mysql-test\mysql-test-run.pl -Destination $Destination\mysql-test
    Copy-Item -Path mysql-test\mysql-stress-test.pl -Destination $Destination\mysql-test
    Copy-Item -Path mysql-test\README -Destination $Destination\mysql-test
    Copy-Item -Path mysql-test\t -Destination $Destination\mysql-test -Recurse
    Copy-Item -Path mysql-test\r -Destination $Destination\mysql-test -Recurse
    Copy-Item -Path mysql-test\include -Destination $Destination\mysql-test -Recurse
    Copy-Item -Path mysql-test\suite -Destination $Destination\mysql-test -Recurse
    Copy-Item -Path mysql-test\std_data -Destination $Destination\mysql-test -Recurse
    Copy-Item -Path mysql-test\lib -Destination $Destination\mysql-test -Recurse
    Copy-Item -Path mysql-test\collections -Destination $Destination\mysql-test -Recurse
    if (Test-Path -Path mysql-test\extra) {
        Copy-Item -Path mysql-test\extra -Destination $Destination\mysql-test -Recurse
    }

    Remove-Item -Path $Destination\mysql-test\lib\My\SafeProcess\my_safe_kill.dir -Recurse
    Remove-Item -Path $Destination\mysql-test\lib\My\SafeProcess\my_safe_process.dir -Recurse
    if (Test-Path -Path $Destination\mysql-test\lib\My\SafeProcess\my_safe_kill.vcproj) {
        Remove-Item -Path $Destination\mysql-test\lib\My\SafeProcess\my_safe_kill.vcproj
    }
    if (Test-Path -Path $Destination\mysql-test\lib\My\SafeProcess\my_safe_process.vcproj) {
        Remove-Item -Path $Destination\mysql-test\lib\My\SafeProcess\my_safe_process.vcproj
    }
    Remove-Item -Path $Destination\mysql-test\lib\My\SafeProcess\RelWithDebInfo\*.ilk
    Remove-Item -Path $Destination\mysql-test\lib\My\SafeProcess\RelWithDebInfo\*.idb

    ### Copy what could be usable in the "scripts" directory
    New-Item -Type Directory -Path $Destination\scripts -ErrorAction Continue | Out-Null
    Copy-Item -Path scripts\mysql_config.pl -Destination $Destination\scripts
    Copy-Item -Path scripts\mysql_convert_table_format.pl -Destination $Destination\scripts
    Copy-Item -Path scripts\mysql_install_db.pl -Destination $Destination\scripts
    Copy-Item -Path scripts\mysql_secure_installation.pl -Destination $Destination\scripts
    Copy-Item -Path scripts\mysqld_multi.pl -Destination $Destination\scripts
    Copy-Item -Path scripts\mysqldumpslow.pl -Destination $Destination\scripts
    Copy-Item -Path scripts\mysqlhotcopy.pl -Destination $Destination\scripts

    Copy-Item -Path sql\share -Destination $Destination -Recurse
    Copy-Item -Path sql-bench -Destination $Destination -Recurse
    Remove-Item $Destination\sql-bench\*.sh
    Remove-Item $Destination\sql-bench\Makefile*

    # The SQL initialisation code is to be in "share"
    Copy-Item -Path scripts\*.sql -Destination $Destination\share

    ### Clean up from possibly copied SCCS directories
    Get-ChildItem -Path $Destination -Filter 'SCCS' -Recurse | Where-Object { $_.PSIsContainer } | Remove-Item -Recurse
}

function Publish-MariaDbBinaries {
    param (
        $MariaDbVersion,
        $MariaDbPackagePath,
        $ApiRepoBaseUrl,
        $GitHubCredentials
    )
    if ($PSBoundParameters.Count -ne 4) { Throw 'Illegal number of arguments' }

    $tag = "v$MariaDbVersion"

    Write-Information '########## Retrieving the release'
    $releaseForTagUrl = "$ApiRepoBaseUrl/releases/tags/$tag"
    $uploadUrlJqExpr = '.upload_url // \"missingRelease\" | split(\"{\")[0]'
    $uploadUrl = Invoke-ApiRequest $GitHubCredentials $releaseForTagUrl $uploadUrlJqExpr
    if ($uploadUrl -eq 'missingRelease') {
        Write-Information "No release found for tag '$tag'"
        Throw
    }
    Write-Information "Upload URL: '$uploadUrl'"

    Write-Information '########## Retrieving binary archive info'
    $name = Split-Path -Path $MariaDbPackagePath -Leaf
    $size = "{0:n1} MiB" -f ((Get-ChildItem $MariaDbPackagePath).Length / 1MB)
    $md5Checksum = (Get-FileHash -Algorithm MD5 -Path $MariaDbPackagePath).Hash |
        Tee-Object -FilePath "$MariaDbPackagePath.md5"
    $sha1Checksum = (Get-FileHash -Algorithm SHA1 -Path $MariaDbPackagePath).Hash |
        Tee-Object -FilePath "$MariaDbPackagePath.sha1"
    $sha256Checksum = (Get-FileHash -Algorithm SHA256 -Path $MariaDbPackagePath).Hash |
        Tee-Object -FilePath "$MariaDbPackagePath.sha256"
    $sha512Checksum = (Get-FileHash -Algorithm SHA512 -Path $MariaDbPackagePath).Hash |
        Tee-Object -FilePath "$MariaDbPackagePath.sha512"
    Write-Information "Name: $name"
    Write-Information "Size: $size"
    Write-Information "MD5: $md5Checksum"
    Write-Information "SHA1: $sha1Checksum"
    Write-Information "SHA256: $sha256Checksum"
    Write-Information "SHA512: $sha512Checksum"

    Write-Information '########## Uploading binary archive'
    $uploadAssetUrl = "${uploadUrl}?name=${name}"
    $response = Invoke-WebRequest `
        -Method Post `
        -Headers (Get-AuthHeaders $GitHubCredentials) `
        -ContentType 'application/gzip' `
        -Infile $MariaDbPackagePath `
        -Uri $uploadAssetUrl `
        2>&1
    if ($response.StatusCode -ne 201) {
        Write-Information "Unable to upload the file '$MariaDbPackagePath`r`n`r`n$response.RawContent"
        Throw
    }

    Write-Information '########## Uploading checksum files'
    Get-ChildItem -Path "$MariaDbPackagePath.*" |
        ForEach-Object {
            $file = $_
            $uploadAssetUrl = "${uploadUrl}?name=$(Split-Path -Path $file -Leaf)"
            $response = Invoke-WebRequest `
                -Method Post `
                -Headers (Get-AuthHeaders $GitHubCredentials) `
                -ContentType 'text/plain' `
                -Infile $file `
                -Uri $uploadAssetUrl `
                2>&1
            if ($response.StatusCode -ne 201) {
                Write-Information "Unable to upload the file '$file'`r`n`r`n$response.RawContent"
                Throw
            }
        }
}

function Get-CommandPath {
    param (
        $Name
    )
    if ($PSBoundParameters.Count -ne 1) { Throw 'Illegal number of arguments' }

    $commandPath = (Get-Command -Name $Name 2>&1).Path
    if ($commandPath -eq $null) {
        Throw "The '$Name' command was not found"
    }

    return $commandPath
}

function Invoke-CommandWithProgress {
    param (
        [ScriptBlock] $ScriptBlock,
        [Object[]] $ArgumentList
    )
    if ($PSBoundParameters.Count -ne 2) { Throw 'Illegal number of arguments' }

    $progressJob = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList

    while ($true) {
        $completedJob = Wait-Job -Job $progressJob -Timeout 4
        if ($completedJob -eq $null) {
            Write-Host -NoNewline '.'
        }
        else {
            Write-Host ''
            Remove-Job -Job $progressJob
            break
        }
    }
}

function Invoke-ApiRequest {
    param (
        $Credentials,
        $Uri,
        $JqExpression
    )
    if ($PSBoundParameters.Count -ne 3) { Throw 'Illegal number of arguments' }

    $oneLineJqExpression = $JqExpression -Replace '\s{2,}', ' '

    $iwrResult = Invoke-WebRequest -Method Get -Headers (Get-AuthHeaders $Credentials) -Uri $Uri 2>&1
    if (-not $? -or $iwrResult.StatusCode -ne 200) {
        Write-Information "Unable to query '$Uri' and parse response with the jq expression '$oneLineJqExpression'"
        Write-Information "iwrResult: $iwrResult"
        Throw
    }

    $jqResult = $iwrResult.Content | jq -r $oneLineJqExpression 2>&1
    if (-not $? -or $jqResult -eq 'null') {
        Write-Information "Unable to query '$Uri' and parse response with the jq expression '$oneLineJqExpression'"
        Write-Information "iwrResult: $iwrResult"
        Write-Information "jqResult: $jqResult"
        Throw
    }

    return $jqResult
}

function Get-AuthHeaders {
    param (
        $Credentials
    )
    if ($PSBoundParameters.Count -ne 1) { Throw 'Illegal number of arguments' }

    $encodedCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Credentials))
    $Headers = @{ Authorization = "Basic $encodedCredentials" }

    return $Headers
}