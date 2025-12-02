BeforeAll {
    $ScriptPath = Join-Path $PSScriptRoot "..\..\powershell\Get-ChangesById.ps1"
}

Describe "Get-ChangesById" {
    BeforeEach {
        $env:GITHUB_OUTPUT = Join-Path $TestDrive "github_output.txt"
        New-Item -Path $env:GITHUB_OUTPUT -ItemType File -Force | Out-Null

        $script:DownloadFolder = Join-Path $TestDrive "download"
    }

    AfterEach {
        Remove-Item -Path $env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
        Remove-Item -Path $script:DownloadFolder -Recurse -ErrorAction SilentlyContinue
    }

    Context "When no changes detected (204 response)" {
        BeforeAll {
            $mockNoChangesResponse = @{
                StatusCode = 204
                Content = ""
            }
        }

        It "Should report no changes for GITHUB vendor" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]$mockNoChangesResponse
            }

            & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -DeploymentId "deployment-123" `
                -TargetEnvironmentAlias "Development" `
                -DownloadFolder $script:DownloadFolder `
                -PipelineVendor "GITHUB"

            $output = Get-Content $env:GITHUB_OUTPUT
            $output | Should -Contain "remoteChanges=no"
        }

        It "Should output no changes message" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]$mockNoChangesResponse
            }

            $output = & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -DeploymentId "deployment-123" `
                -TargetEnvironmentAlias "Development" `
                -DownloadFolder $script:DownloadFolder `
                -PipelineVendor "TESTRUN" 6>&1

            $outputString = $output -join "`n"
            $outputString | Should -Match "No Changes"
        }
    }

    Context "When changes detected (200 response)" {
        BeforeAll {
            $mockChangesResponse = @{
                StatusCode = 200
                Content = "diff --git a/file.txt b/file.txt`nsome patch content"
            }
        }

        It "Should report changes for GITHUB vendor" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]$mockChangesResponse
            }

            & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -DeploymentId "deployment-123" `
                -TargetEnvironmentAlias "Development" `
                -DownloadFolder $script:DownloadFolder `
                -PipelineVendor "GITHUB"

            $output = Get-Content $env:GITHUB_OUTPUT
            $output | Should -Contain "remoteChanges=yes"
        }

        It "Should output changes detected message" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]$mockChangesResponse
            }

            $output = & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -DeploymentId "deployment-123" `
                -TargetEnvironmentAlias "Development" `
                -DownloadFolder $script:DownloadFolder `
                -PipelineVendor "TESTRUN" 6>&1

            $outputString = $output -join "`n"
            $outputString | Should -Match "Changes detected"
        }

        It "Should output Azure DevOps variable format" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]$mockChangesResponse
            }

            $output = & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -DeploymentId "deployment-123" `
                -TargetEnvironmentAlias "Development" `
                -DownloadFolder $script:DownloadFolder `
                -PipelineVendor "AZUREDEVOPS" 6>&1

            $vsoOutput = $output | Where-Object { $_ -match "##vso\[task\.setvariable" }
            $vsoOutput | Should -Not -BeNullOrEmpty
            $vsoOutput[0] | Should -BeLike "*remoteChanges*yes*"
        }
    }

    Context "When using custom BaseUrl" {
        It "Should use custom BaseUrl when provided" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]@{
                    StatusCode = 204
                    Content = ""
                }
            } -Verifiable

            & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -DeploymentId "deployment-123" `
                -TargetEnvironmentAlias "Development" `
                -DownloadFolder $script:DownloadFolder `
                -PipelineVendor "TESTRUN" `
                -BaseUrl "https://custom.api.com"

            Should -Invoke Invoke-WebRequest -ParameterFilter {
                $URI -like "https://custom.api.com/*"
            }
        }
    }

    Context "When using unsupported vendor" {
        It "Should have error handling for unknown vendor in script" {
            $scriptContent = Get-Content $ScriptPath -Raw
            $scriptContent | Should -Match 'Default[\s\S]*Exit 1'
            $scriptContent | Should -Match 'Please use one of the supported Pipeline Vendors'
        }
    }

    Context "When API returns error" {
        It "Should output error on HTTP error" {
            Mock Invoke-WebRequest {
                throw [System.Net.WebException]::new("Unauthorized")
            }

            $output = & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "invalid-key" `
                -DeploymentId "deployment-123" `
                -TargetEnvironmentAlias "Development" `
                -DownloadFolder $script:DownloadFolder `
                -PipelineVendor "TESTRUN" 6>&1 2>&1

            $outputString = $output -join "`n"
            $outputString | Should -Match "---Error---"
        }

        It "Should include exception message in error output" {
            Mock Invoke-WebRequest {
                throw [System.Net.WebException]::new("Connection refused")
            }

            $output = & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -DeploymentId "deployment-123" `
                -TargetEnvironmentAlias "Development" `
                -DownloadFolder $script:DownloadFolder `
                -PipelineVendor "TESTRUN" 6>&1 2>&1

            $outputString = $output -join "`n"
            $outputString | Should -Match "Exception Message:"
        }
    }

    Context "Download folder handling" {
        It "Should create download folder if it does not exist" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]@{
                    StatusCode = 204
                    Content = ""
                }
            }

            $newFolder = Join-Path $TestDrive "new-folder"

            & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -DeploymentId "deployment-123" `
                -TargetEnvironmentAlias "Development" `
                -DownloadFolder $newFolder `
                -PipelineVendor "TESTRUN"

            Test-Path $newFolder | Should -Be $true
        }
    }
}
