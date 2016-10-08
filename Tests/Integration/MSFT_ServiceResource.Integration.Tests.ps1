if ($PSVersionTable.PSVersion.Major -lt 5 -or $PSVersionTable.PSVersion.Minor -lt 1)
{
    Write-Warning -Message 'Cannot run PSDscResources integration tests on PowerShell versions lower than 5.1'
    return
}

$script:DscResourceName = 'MSFT_ServiceResource'

Import-Module -Name (Join-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'TestHelpers') -ChildPath 'CommonTestHelper.psm1')

$script:testEnvironment = Enter-DscResourceTestEnvironment `
    -DscResourceModuleName 'PSDscResources' `
    -DscResourceName 'MSFT_ServiceResource' `
    -TestType 'Integration'

Import-Module -Name (Join-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'DscResource.Tests') -ChildPath 'TestHelper.psm1')

try
{
    $script:testServiceName = 'DscTestService'
    $script:testServiceCodePath = Join-Path -Path (Split-Path $PSScriptRoot -Parent) -ChildPath 'TestHelpers\DscTestService.cs'
    $script:testServiceDisplayName = 'DSC test service display name'
    $script:testServiceDescription = 'This is a DSC test service used for integration testing MSFT_ServiceResource'
    $script:testServiceDependsOn = 'winrm'
    $script:testServiceExecutablePath = Join-Path -Path $ENV:Temp -ChildPath 'DscTestService.exe'
    $script:testServiceNewCodePath = Join-Path -Path (Split-Path $PSScriptRoot -Parent) -ChildPath 'TestHelpers\DscTestService.cs'
    $script:testServiceNewDisplayName = 'New: DSC test service display name'
    $script:testServiceNewDescription = 'New: This is a DSC test service used for integration testing MSFT_ServiceResource'
    $script:testServiceNewDependsOn = 'spooler'
    $script:testServiceNewExecutablePath = Join-Path -Path $ENV:Temp -ChildPath 'NewDscTestService.exe'
    
    <#
        Nano Server doesn't recognize 'spooler', so if these tests are being run on Nano
        this value must stay as 'winrm'
    #>
    if ($PSVersionTable.PSEdition -ieq 'Core') { $script:testServiceNewDependsOn = 'winrm' }

    Import-Module -Name (Join-Path -Path (Split-Path $PSScriptRoot -Parent) `
                               -ChildPath 'TestHelpers\MSFT_ServiceResource.TestHelper.psm1') `
                               -Force

    Stop-Service $script:testServiceName -ErrorAction SilentlyContinue

    # Create new Service binaries for the new service.
    New-ServiceBinary `
        -ServiceName $script:testServiceName `
        -ServiceCodePath $script:testServiceCodePath `
        -ServiceDisplayName $script:testServiceDisplayName `
        -ServiceDescription $script:testServiceDescription `
        -ServiceDependsOn $script:testServiceDependsOn `
        -ServiceExecutablePath $script:testServiceExecutablePath

    New-ServiceBinary `
        -ServiceName $script:testServiceName `
        -ServiceCodePath $script:testServiceNewCodePath `
        -ServiceDisplayName $script:testServiceNewDisplayName `
        -ServiceDescription $script:testServiceNewDescription `
        -ServiceDependsOn $script:testServiceNewDependsOn `
        -ServiceExecutablePath $script:testServiceExecutablePath

    #region Integration Tests
    $configFile = Join-Path -Path $PSScriptRoot -ChildPath "$($script:DscResourceName)_Add.config.ps1"
    . $configFile

    Describe "$($script:DscResourceName) Add Service" {

        It 'Should compile and apply the MOF without throwing' {
            {
                & "$($script:DscResourceName)_Add_Config" `
                    -OutputPath $script:testEnvironment.WorkingFolder `
                    -ServiceName $script:testServiceName `
                    -ServicePath $script:testServiceExecutablePath `
                    -ServiceDisplayName $script:testServiceDisplayName `
                    -ServiceDescription $script:testServiceDescription `
                    -ServiceDependsOn $script:testServiceDependsOn

                Start-DscConfiguration -Path $script:testEnvironment.WorkingFolder `
                                       -ComputerName localhost -Wait -Verbose -Force
            } | Should Not Throw
        }

        It 'Should be able to call Get-DscConfiguration without throwing' {
            { Get-DscConfiguration -Verbose -ErrorAction Stop } | Should Not Throw
        }

        $script:service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($script:testServiceName)'"
        It 'Should return a service of type CimInstance' {
            $script:service | Should BeOfType 'Microsoft.Management.Infrastructure.CimInstance'
        }

        It 'Should have set the resource and all the parameters should match' {
            # Get the current service details
            $script:service.status                | Should Be 'OK'
            $script:service.pathname              | Should Be $script:testServiceExecutablePath
            $script:service.description           | Should Be $script:testServiceDescription
            $script:service.displayname           | Should Be $script:testServiceDisplayName
            $script:service.started               | Should Be $true
            $script:service.state                 | Should Be 'Running'
            $script:service.desktopinteract       | Should Be $true
            $script:service.startname             | Should Be 'LocalSystem'
            $script:service.startmode             | Should Be 'Auto'
        }
    }

    Reset-DSC

    $configFile = Join-Path -Path $PSScriptRoot -ChildPath "$($script:DscResourceName)_Edit.config.ps1"
    . $configFile

    Describe "$($script:DscResourceName) Edit Service" {

        It 'Should compile and apply the MOF without throwing' {
            {
                & "$($script:DscResourceName)_Edit_Config" `
                    -OutputPath $script:testEnvironment.WorkingFolder `
                    -ServiceName $script:testServiceName `
                    -ServicePath $script:testServiceNewExecutablePath `
                    -ServiceDisplayName $script:testServiceNewDisplayName `
                    -ServiceDescription $script:testServiceNewDescription `
                    -ServiceDependsOn $script:testServiceNewDependsOn

                Start-DscConfiguration -Path $script:testEnvironment.WorkingFolder `
                                       -ComputerName localhost -Wait -Verbose -Force
            } | Should Not Throw
        }

        It 'Should be able to call Get-DscConfiguration without throwing' {
            { Get-DscConfiguration -Verbose -ErrorAction Stop } | Should Not Throw
        }

        # Get the current service details
        $script:service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($script:testServiceName)'"
        It 'Should return a service or type CimInstance' {
            $script:service | Should BeOfType 'Microsoft.Management.Infrastructure.CimInstance'
        }

        It 'Should have set the resource and all the parameters should match' {
            # Get the current service details
            $script:service.status                | Should Be 'OK'
            $script:service.pathname              | Should Be $script:testServiceNewExecutablePath
            $script:service.description           | Should Be $script:testServiceNewDescription
            $script:service.displayname           | Should Be $script:testServiceNewDisplayName
            $script:service.started               | Should Be $false
            $script:service.state                 | Should Be 'Stopped'
            $script:service.desktopinteract       | Should Be $false
            $script:service.startname             | Should Be 'NT Authority\LocalService'
            $script:service.startmode             | Should Be 'Manual'
        }
    }

    Reset-DSC

    $configFile = Join-Path -Path $PSScriptRoot -ChildPath "$($script:DscResourceName)_Remove.config.ps1"
    . $configFile

    Describe "$($script:DscResourceName) Remove Service" {

        It 'Should compile and apply the MOF without throwing' {
            {
                & "$($script:DscResourceName)_Remove_Config" `
                    -OutputPath $script:testEnvironment.WorkingFolder `
                    -ServiceName $script:testServiceName

                Start-DscConfiguration -Path $script:testEnvironment.WorkingFolder `
                                       -ComputerName localhost -Wait -Verbose -Force
            } | Should not throw
        }

        It 'Should be able to call Get-DscConfiguration without throwing' {
            { Get-DscConfiguration -Verbose -ErrorAction Stop } | Should Not throw
        }

        # Get the current service details
        $script:service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($script:testServiceName)'"

        It 'Should return the service as null' {
            $script:service | Should BeNullOrEmpty
        }
    }
    #endregion
}
finally
{
    # Clean up
    Remove-TestService `
        -ServiceName $script:testServiceName `
        -ServiceExecutablePath $script:testServiceExecutablePath

    Exit-DscResourceTestEnvironment -TestEnvironment $script:testEnvironment
}
