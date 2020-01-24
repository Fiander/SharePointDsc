[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
param
(
    [Parameter()]
    [string]
    $SharePointCmdletModule = (Join-Path -Path $PSScriptRoot `
            -ChildPath "..\Stubs\SharePoint\15.0.4805.1000\Microsoft.SharePoint.PowerShell.psm1" `
            -Resolve)
)

$script:DSCModuleName = 'SharePointDsc'
$script:DSCResourceName = 'SPUserProfileSyncService'
$script:DSCResourceFullName = 'MSFT_' + $script:DSCResourceName

function Invoke-TestSetup
{
    try
    {
        Import-Module -Name DscResource.Test -Force

        Import-Module -Name (Join-Path -Path $PSScriptRoot `
                -ChildPath "..\UnitTestHelper.psm1" `
                -Resolve)

        $Global:SPDscHelper = New-SPDscUnitTestHelper -SharePointStubModule $SharePointCmdletModule `
            -DscResource $script:DSCResourceName
    }
    catch [System.IO.FileNotFoundException]
    {
        throw 'DscResource.Test module dependency not found. Please run ".\build.ps1 -Tasks build" first.'
    }

    $script:testEnvironment = Initialize-TestEnvironment `
        -DSCModuleName $script:DSCModuleName `
        -DSCResourceName $script:DSCResourceFullName `
        -ResourceType 'Mof' `
        -TestType 'Unit'
}

function Invoke-TestCleanup
{
    Restore-TestEnvironment -TestEnvironment $script:testEnvironment
}

Invoke-TestSetup

try
{
    Describe -Name $Global:SPDscHelper.DescribeHeader -Fixture {
        InModuleScope -ModuleName $Global:SPDscHelper.ModuleName -ScriptBlock {
            Invoke-Command -ScriptBlock $Global:SPDscHelper.InitializeScript -NoNewScope

            # Initialize tests
            $getTypeFullName = "Microsoft.Office.Server.Administration.UserProfileApplication"
            $mockPassword = ConvertTo-SecureString -String "password" -AsPlainText -Force
            $mockCredential = New-Object -TypeName System.Management.Automation.PSCredential `
                -ArgumentList @("$($Env:USERDOMAIN)\$($Env:USERNAME)", $mockPassword)
            $mockFarmCredential = New-Object -TypeName System.Management.Automation.PSCredential `
                -ArgumentList @("DOMAIN\sp_farm", $mockPassword)

            # Mocks for all contexts
            Mock -CommandName Clear-SPDscKerberosToken -MockWith { }
            Mock -CommandName Get-SPDscFarmAccount -MockWith {
                return $mockFarmCredential
            }
            Mock -CommandName Start-SPServiceInstance -MockWith { }
            Mock -CommandName Stop-SPServiceInstance -MockWith { $Global:ServiceStatus = "Disabled" }
            Mock -CommandName Restart-Service -MockWith { }
            Mock -CommandName Add-SPDscUserToLocalAdmin -MockWith { }
            Mock -CommandName Test-SPDscUserIsLocalAdmin -MockWith {
                return $false
            }
            Mock -CommandName Remove-SPDscUserToLocalAdmin -MockWith { }
            Mock -CommandName Start-Sleep -MockWith { }
            Mock -CommandName Get-SPServiceApplication -MockWith {
                return @(
                    New-Object -TypeName "Object" |
                    Add-Member -MemberType NoteProperty `
                        -Name TypeName `
                        -Value "User Profile Service Application" `
                        -PassThru |
                    Add-Member -MemberType NoteProperty `
                        -Name DisplayName `
                        -Value "User Profile Service Service App" `
                        -PassThru |
                    Add-Member -MemberType NoteProperty `
                        -Name ApplicationPool `
                        -Value @{
                        Name = "Service Pool"
                    } -PassThru |
                    Add-Member -MemberType ScriptMethod `
                        -Name GetType `
                        -Value {
                        New-Object -TypeName "Object" |
                        Add-Member -MemberType NoteProperty `
                            -Name FullName `
                            -Value $getTypeFullName `
                            -PassThru |
                        Add-Member -MemberType ScriptMethod `
                            -Name GetProperties `
                            -Value {
                            param($x)
                            return @(
                                (New-Object -TypeName "Object" |
                                    Add-Member -MemberType NoteProperty `
                                        -Name Name `
                                        -Value "SocialDatabase" `
                                        -PassThru |
                                    Add-Member -MemberType ScriptMethod `
                                        -Name GetValue `
                                        -Value {
                                        param($x)
                                        return @{
                                            Name   = "SP_SocialDB"
                                            Server = @{
                                                Name = "SQL.domain.local"
                                            }
                                        }
                                    } -PassThru
                                ),
                                (New-Object -TypeName "Object" |
                                    Add-Member -MemberType NoteProperty `
                                        -Name Name `
                                        -Value "ProfileDatabase" `
                                        -PassThru |
                                    Add-Member -MemberType ScriptMethod `
                                        -Name GetValue `
                                        -Value {
                                        return @{
                                            Name   = "SP_ProfileDB"
                                            Server = @{
                                                Name = "SQL.domain.local"
                                            }
                                        }
                                    } -PassThru
                                ),
                                (New-Object -TypeName "Object" |
                                    Add-Member -MemberType NoteProperty `
                                        -Name Name `
                                        -Value "SynchronizationDatabase" `
                                        -PassThru |
                                    Add-Member -MemberType ScriptMethod `
                                        -Name GetValue `
                                        -Value {
                                        return @{
                                            Name   = "SP_ProfileSyncDB"
                                            Server = @{
                                                Name = "SQL.domain.local"
                                            }
                                        }
                                    } -PassThru
                                )
                            )
                        } -PassThru
                    } -PassThru -Force
                )
            }

            # Test contexts
            switch ($Global:SPDscHelper.CurrentStubBuildNumber.Major)
            {
                15
                {
                    Context -Name "When PSDSCRunAsCredential is not the Farm Account" -Fixture {
                        $testParams = @{
                            UserProfileServiceAppName = "User Profile Sync Service App"
                            FarmAccount               = $mockCredential
                            Ensure                    = "Present"
                        }

                        Mock -CommandName Get-SPDscFarmAccount -MockWith {
                            return $mockCredential
                        }

                        Mock -CommandName Get-SPServiceInstance -MockWith {
                            return $null
                        }

                        It "Should throw exception in the get method" {
                            { Get-TargetResource @testParams } | Should throw "Specified PSDSCRunAsCredential "
                        }

                        It "Should throw exception in the test method" {
                            { Test-TargetResource @testParams } | Should throw "Specified PSDSCRunAsCredential "
                        }

                        It "Should throw exception in the set method" {
                            { Set-TargetResource @testParams } | Should throw "Specified PSDSCRunAsCredential "
                        }
                    }

                    Context -Name "When InstallAccount is the Farm Account" -Fixture {
                        $testParams = @{
                            UserProfileServiceAppName = "User Profile Service Service App"
                            FarmAccount               = $mockCredential
                            Ensure                    = "Present"
                            InstallAccount            = $mockFarmCredential
                        }

                        Mock -CommandName Get-SPServiceInstance -MockWith {
                            return $null
                        }

                        It "Should throw exception in the get method" {
                            { Get-TargetResource @testParams } | Should throw "Specified InstallAccount "
                        }

                        It "Should throw exception in the test method" {
                            { Test-TargetResource @testParams } | Should throw "Specified InstallAccount "
                        }

                        It "Should throw exception in the set method" {
                            { Set-TargetResource @testParams } | Should throw "Specified InstallAccount "
                        }
                    }

                    Context -Name "User profile sync service is not found locally" -Fixture {
                        $testParams = @{
                            UserProfileServiceAppName = "User Profile Service Service App"
                            FarmAccount               = $mockCredential
                            Ensure                    = "Present"
                        }

                        Mock -CommandName Get-SPServiceInstance -MockWith {
                            return $null
                        }

                        It "Should return absent from the get method" {
                            $Global:SPDscUPACheck = $false
                            (Get-TargetResource @testParams).Ensure | Should Be "Absent"
                        }
                    }

                    Context -Name "User profile sync service is not running and should be" -Fixture {
                        $testParams = @{
                            UserProfileServiceAppName = "User Profile Service Service App"
                            FarmAccount               = $mockCredential
                            Ensure                    = "Present"
                        }

                        Mock -CommandName Get-SPServiceInstance -MockWith {
                            $spSvcInstance = [pscustomobject]@{
                                ID       = [Guid]::Parse("21946987-5163-418f-b781-2beb83aa191f")
                                TypeName = "User Profile Synchronization Service"
                            }
                            $spSvcInstance = $spSvcInstance | Add-Member ScriptMethod GetType {
                                return @{ Name = "ProfileSynchronizationServiceInstance" }
                            } -PassThru -Force
                            if ($Global:SPDscUPACheck -eq $false)
                            {
                                $Global:SPDscUPACheck = $true
                                $spSvcInstance = $spSvcInstance | Add-Member NoteProperty Status "Disabled" -PassThru
                                $spSvcInstance = $spSvcInstance | Add-Member NoteProperty UserProfileApplicationGuid [Guid]::Empty -PassThru
                            }
                            else
                            {
                                $spSvcInstance = $spSvcInstance | Add-Member NoteProperty Status "Online" -PassThru
                                $spSvcInstance = $spSvcInstance | Add-Member NoteProperty UserProfileApplicationGuid ([Guid]::NewGuid()) -PassThru
                            }
                            return $spSvcInstance
                        }

                        Mock -CommandName Get-SPServiceApplication -MockWith {
                            return @(
                                New-Object -TypeName "Object" |
                                Add-Member -MemberType NoteProperty `
                                    -Name ID `
                                    -Value ([Guid]::Parse("21946987-5163-418f-b781-2beb83aa191f")) `
                                    -PassThru |
                                Add-Member -MemberType ScriptMethod `
                                    -Name GetType `
                                    -Value {
                                    New-Object -TypeName "Object" |
                                    Add-Member -MemberType NoteProperty `
                                        -Name FullName `
                                        -Value $getTypeFullName `
                                        -PassThru
                                } `
                                    -PassThru -Force |
                                Add-Member -MemberType ScriptMethod `
                                    -Name SetSynchronizationMachine `
                                    -Value {
                                    param(
                                        $computerName,
                                        $syncServiceID,
                                        $FarmUserName,
                                        $FarmPassword
                                    )
                                } -PassThru
                            )
                        }

                        It "Should return absent from the get method" {
                            $Global:SPDscUPACheck = $false
                            (Get-TargetResource @testParams).Ensure | Should Be "Absent"
                        }

                        It "Should return false from the test method" {
                            $Global:SPDscUPACheck = $false
                            Test-TargetResource @testParams | Should Be $false
                        }

                        It "Should call the start service cmdlet from the set method" {
                            $Global:SPDscUPACheck = $false
                            Set-TargetResource @testParams

                            Assert-MockCalled Start-SPServiceInstance
                        }

                        $Global:SPDscUPACheck = $false
                        Mock -CommandName Get-SPServiceApplication -MockWith {
                            return $null
                        }

                        It "Should throw in the set method if the user profile service app can't be found" {
                            { Set-TargetResource @testParams } | Should Throw
                        }
                    }

                    Context -Name "User profile sync service is running and should be" -Fixture {
                        $testParams = @{
                            UserProfileServiceAppName = "User Profile Service Service App"
                            FarmAccount               = $mockCredential
                            Ensure                    = "Present"
                        }

                        Mock -CommandName Get-SPServiceInstance -MockWith {
                            $spSvcInstance = [pscustomobject]@{
                                ID       = [Guid]::Parse("21946987-5163-418f-b781-2beb83aa191f")
                                TypeName = "User Profile Synchronization Service"
                            }
                            $spSvcInstance = $spSvcInstance | Add-Member ScriptMethod GetType {
                                return @{ Name = "ProfileSynchronizationServiceInstance" }
                            } -PassThru -Force
                            $spSvcInstance = $spSvcInstance | Add-Member NoteProperty Status "Online" -PassThru
                            $spSvcInstance = $spSvcInstance | Add-Member NoteProperty UserProfileApplicationGuid ([Guid]::NewGuid()) -PassThru
                            return $spSvcInstance
                        }

                        It "Should return present from the get method" {
                            (Get-TargetResource @testParams).Ensure | Should Be "Present"
                        }

                        It "Should return true from the test method" {
                            Test-TargetResource @testParams | Should Be $true
                        }
                    }

                    Context -Name "User profile sync service is running and shouldn't be" -Fixture {
                        $testParams = @{
                            UserProfileServiceAppName = "User Profile Service Service App"
                            FarmAccount               = $mockCredential
                            Ensure                    = "Absent"
                        }

                        Mock -CommandName Get-SPServiceInstance -MockWith {
                            $spSvcInstance = [pscustomobject]@{
                                ID       = [Guid]::Parse("21946987-5163-418f-b781-2beb83aa191f")
                                TypeName = "User Profile Synchronization Service"
                            }
                            $spSvcInstance = $spSvcInstance | Add-Member ScriptMethod GetType {
                                return @{ Name = "ProfileSynchronizationServiceInstance" }
                            } -PassThru -Force
                            if ($Global:SPDscUPACheck -eq $false)
                            {
                                $Global:SPDscUPACheck = $true
                                $spSvcInstance = $spSvcInstance | Add-Member NoteProperty Status "Online" -PassThru
                                $spSvcInstance = $spSvcInstance | Add-Member NoteProperty UserProfileApplicationGuid ([Guid]::NewGuid()) -PassThru
                            }
                            else
                            {
                                $spSvcInstance = $spSvcInstance | Add-Member NoteProperty Status "Disabled" -PassThru
                                $spSvcInstance = $spSvcInstance | Add-Member NoteProperty UserProfileApplicationGuid [Guid]::Empty -PassThru
                            }
                            return $spSvcInstance
                        }

                        It "Should return present from the get method" {
                            $Global:SPDscUPACheck = $false
                            (Get-TargetResource @testParams).Ensure | Should Be "Present"
                        }

                        It "Should return false from the test method" {
                            $Global:SPDscUPACheck = $false
                            Test-TargetResource @testParams | Should Be $false
                        }

                        It "Should call the stop service cmdlet from the set method" {
                            $Global:SPDscUPACheck = $false
                            Set-TargetResource @testParams

                            Assert-MockCalled Stop-SPServiceInstance
                        }
                    }

                    Context -Name "User profile sync service is not running and shouldn't be" -Fixture {
                        $testParams = @{
                            UserProfileServiceAppName = "User Profile Service Service App"
                            FarmAccount               = $mockCredential
                            Ensure                    = "Absent"
                        }

                        Mock -CommandName Get-SPServiceInstance -MockWith {
                            $spSvcInstance = [pscustomobject]@{
                                ID       = [Guid]::Parse("21946987-5163-418f-b781-2beb83aa191f")
                                TypeName = "User Profile Synchronization Service"
                            }
                            $spSvcInstance = $spSvcInstance | Add-Member ScriptMethod GetType {
                                return @{ Name = "ProfileSynchronizationServiceInstance" }
                            } -PassThru -Force
                            $spSvcInstance = $spSvcInstance | Add-Member NoteProperty Status "Disabled" -PassThru
                            $spSvcInstance = $spSvcInstance | Add-Member NoteProperty UserProfileApplicationGuid [Guid]::Empty -PassThru
                            return $spSvcInstance
                        }

                        It "Should return absent from the get method" {
                            (Get-TargetResource @testParams).Ensure | Should Be "Absent"
                        }

                        It "Should return true from the test method" {
                            Test-TargetResource @testParams | Should Be $true
                        }
                    }

                    Context -Name "User profile sync service is not running and shouldn't be because the database is read only" -Fixture {
                        $testParams = @{
                            UserProfileServiceAppName = "User Profile Service Service App"
                            FarmAccount               = $mockCredential
                            Ensure                    = "Present"
                            RunOnlyWhenWriteable      = $true
                        }

                        Mock -CommandName Get-SPServiceInstance -MockWith {
                            $spSvcInstance = [pscustomobject]@{
                                ID       = [Guid]::Parse("21946987-5163-418f-b781-2beb83aa191f")
                                TypeName = "User Profile Synchronization Service"
                            }
                            $spSvcInstance = $spSvcInstance | Add-Member ScriptMethod GetType {
                                return @{ Name = "ProfileSynchronizationServiceInstance" }
                            } -PassThru -Force
                            $spSvcInstance = $spSvcInstance | Add-Member NoteProperty Status "Disabled" -PassThru
                            $spSvcInstance = $spSvcInstance | Add-Member NoteProperty UserProfileApplicationGuid ([Guid]::NewGuid()) -PassThru
                            return $spSvcInstance
                        }

                        Mock -CommandName Get-SPDatabase -MockWith {
                            return @(
                                @{
                                    Name        = "SP_ProfileDB"
                                    IsReadyOnly = $true
                                }
                            )
                        }

                        It "Should return absent from the get method" {
                            (Get-TargetResource @testParams).Ensure | Should Be "Absent"
                        }

                        It "Should return true from the test method" {
                            Test-TargetResource @testParams | Should Be $true
                        }
                    }

                    Context -Name "User profile sync service is running and shouldn't be because the database is read only" -Fixture {
                        $testParams = @{
                            UserProfileServiceAppName = "User Profile Service Service App"
                            FarmAccount               = $mockCredential
                            Ensure                    = "Present"
                            RunOnlyWhenWriteable      = $true
                        }
                        $Global:ServiceStatus = "Online"

                        Mock -CommandName Get-SPServiceInstance -MockWith {
                            $spSvcInstance = [pscustomobject]@{
                                ID       = [Guid]::Parse("21946987-5163-418f-b781-2beb83aa191f")
                                TypeName = "User Profile Synchronization Service"
                            }
                            $spSvcInstance = $spSvcInstance | Add-Member ScriptMethod GetType {
                                return @{ Name = "ProfileSynchronizationServiceInstance" }
                            } -PassThru -Force
                            $spSvcInstance | Add-Member ScriptProperty Status {
                                return $Global:ServiceStatus
                            }
                            $spSvcInstance = $spSvcInstance | Add-Member NoteProperty UserProfileApplicationGuid ([Guid]::NewGuid()) -PassThru
                            return $spSvcInstance
                        }

                        Mock -CommandName Get-SPDatabase -MockWith {
                            return @(
                                @{
                                    Name        = "SP_ProfileDB"
                                    IsReadyOnly = $true
                                }
                            )
                        }

                        It "Should return present from the get method" {
                            (Get-TargetResource @testParams).Ensure | Should Be "Present"
                        }

                        It "Should return false from the test method" {
                            Test-TargetResource @testParams | Should Be $false
                        }

                        It "Should call the stop service cmdlet from the set method" {
                            $Global:SPDscUPACheck = $false
                            Set-TargetResource @testParams

                            Assert-MockCalled Stop-SPServiceInstance
                        }
                    }
                    Context -Name "User profile sync service is not found" -Fixture {
                        $testParams = @{
                            UserProfileServiceAppName = "User Profile Service Service App"
                            FarmAccount               = $mockCredential
                            Ensure                    = "Present"
                            RunOnlyWhenWriteable      = $true
                        }

                        Mock -CommandName Get-SPServiceInstance -MockWith {
                            $spSvcInstance = [pscustomobject]@{
                                ID = [Guid]::Parse("21946987-5163-418f-b781-2beb83aa191f")
                            }
                            $spSvcInstance = $spSvcInstance | Add-Member ScriptMethod GetType {
                                return @{ Name = "FakeServiceInstance" }
                            } -PassThru -Force
                            return $spSvcInstance
                        }

                        It "Should return present from the get method" {
                            (Get-TargetResource @testParams).Ensure | Should Be "Absent"
                        }

                        It "Should throw an error from the set method" {
                            { Set-TargetResource @testParams } | Should throw
                        }
                    }

                    Context -Name "Can't get the Farm Account" -Fixture {
                        $testParams = @{
                            UserProfileServiceAppName = "User Profile Service Service App"
                            FarmAccount               = $mockCredential
                            Ensure                    = "Present"
                            RunOnlyWhenWriteable      = $true
                        }

                        Mock -CommandName Get-SPDscFarmAccount -MockWith {
                            return $null
                        }

                        It "Should throw an error from the get method" {
                            { (Get-TargetResource @testParams).Ensure } | Should throw "Unable to retrieve the Farm Account. Check if the farm exists."
                        }

                        It "Should throw an error from the set method" {
                            { Set-TargetResource @testParams } | Should throw "Unable to retrieve the Farm Account. Check if the farm exists."
                        }
                    }
                }
                16
                {
                    Context -Name "All methods throw exceptions as user profile sync doesn't exist in 2016" -Fixture {
                        $testParams = @{
                            UserProfileServiceAppName = "User Profile Service Service App"
                            FarmAccount               = $mockCredential
                        }

                        It "Should throw on the get method" {
                            { Get-TargetResource @testParams } | Should Throw
                        }

                        It "Should throw on the test method" {
                            { Test-TargetResource @testParams } | Should Throw
                        }

                        It "Should throw on the set method" {
                            { Set-TargetResource @testParams } | Should Throw
                        }
                    }
                }
            }
        }
    }
}
finally
{
    Invoke-TestCleanup
}
