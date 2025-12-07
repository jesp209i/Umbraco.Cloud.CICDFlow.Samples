BeforeAll {
    $ScriptPath = Join-Path $PSScriptRoot "..\..\V2\powershell\Get-LatestDeployment.ps1"
}

Describe "Get-LatestDeployment" {
    BeforeEach {
        # Set up test environment variable for GitHub output
        $env:GITHUB_OUTPUT = Join-Path $TestDrive "github_output.txt"
        New-Item -Path $env:GITHUB_OUTPUT -ItemType File -Force | Out-Null
    }

    AfterEach {
        Remove-Item -Path $env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
    }

    Context "When deployment exists" {
        BeforeAll {
            $mockDeploymentId = "12345678-1234-1234-1234-123456789abc"
            $mockResponse = @{
                StatusCode = 200
                Content = @{
                    data = @(
                        @{ id = $mockDeploymentId }
                    )
                } | ConvertTo-Json -Depth 3
            }
        }

        It "Should return deployment ID for GITHUB vendor" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]$mockResponse
            }

            & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -TargetEnvironmentAlias "Development" `
                -PipelineVendor "GITHUB"

            $output = Get-Content $env:GITHUB_OUTPUT
            $output | Should -Contain "latestDeploymentId=$mockDeploymentId"
        }

        It "Should call API with correct URL and headers" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]$mockResponse
            } -Verifiable

            & $ScriptPath `
                -ProjectId "my-project-id" `
                -ApiKey "my-api-key" `
                -TargetEnvironmentAlias "Live" `
                -PipelineVendor "TESTRUN"

            Should -InvokeVerifiable
            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $URI -like "*my-project-id*" -and
                $URI -like "*targetEnvironmentAlias=Live*" -and
                $Headers['Umbraco-Cloud-Api-Key'] -eq "my-api-key"
            }
        }

        It "Should use custom BaseUrl when provided" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]$mockResponse
            }

            & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -TargetEnvironmentAlias "Development" `
                -PipelineVendor "TESTRUN" `
                -BaseUrl "https://custom.api.com"

            Should -Invoke Invoke-WebRequest -ParameterFilter {
                $URI -like "https://custom.api.com/*"
            }
        }
    }

    Context "When no deployments exist" {
        BeforeAll {
            $mockEmptyResponse = @{
                StatusCode = 200
                Content = @{
                    data = @()
                } | ConvertTo-Json -Depth 3
            }
        }

        It "Should output empty deployment ID for GITHUB" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]$mockEmptyResponse
            }

            & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -TargetEnvironmentAlias "Development" `
                -PipelineVendor "GITHUB"

            $output = Get-Content $env:GITHUB_OUTPUT
            $output | Should -Contain "latestDeploymentId="
        }
    }

    Context "When using AZUREDEVOPS vendor" {
        BeforeAll {
            $mockDeploymentId = "abcd-1234"
            $mockResponse = @{
                StatusCode = 200
                Content = @{
                    data = @(
                        @{ id = $mockDeploymentId }
                    )
                } | ConvertTo-Json -Depth 3
            }
        }

        It "Should output Azure DevOps variable format" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]$mockResponse
            }

            $output = & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -TargetEnvironmentAlias "Development" `
                -PipelineVendor "AZUREDEVOPS" 6>&1

            $vsoOutput = $output | Where-Object { $_ -match "##vso\[task\.setvariable" }
            $vsoOutput | Should -Not -BeNullOrEmpty
            $vsoOutput[0] | Should -BeLike "*latestDeploymentId*$mockDeploymentId*"
        }
    }

    Context "When using unsupported vendor" {
        BeforeAll {
            $mockResponse = @{
                StatusCode = 200
                Content = @{
                    data = @(
                        @{ id = "some-id" }
                    )
                } | ConvertTo-Json -Depth 3
            }
        }

        It "Should exit with code 1 for unknown vendor" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]$mockResponse
            }

            $result = pwsh -Command "& '$ScriptPath' -ProjectId 'test' -ApiKey 'key' -TargetEnvironmentAlias 'Dev' -PipelineVendor 'UNKNOWN'; exit `$LASTEXITCODE"
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context "When API returns error" {
        It "Should exit with code 1 on HTTP error" {
            # Run in subprocess to capture exit code
            $result = pwsh -Command "
                Mock Invoke-WebRequest { throw 'API Error' }
                & '$ScriptPath' -ProjectId 'test' -ApiKey 'key' -TargetEnvironmentAlias 'Dev' -PipelineVendor 'GITHUB'
                exit `$LASTEXITCODE
            " 2>&1
            $LASTEXITCODE | Should -Be 1
        }

        It "Should output error marker and exception message" {
            Mock Invoke-WebRequest {
                throw [System.Net.WebException]::new("Connection refused")
            }

            $output = & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -TargetEnvironmentAlias "Development" `
                -PipelineVendor "TESTRUN" 6>&1 2>&1

            $outputString = $output -join "`n"
            $outputString | Should -Match "---Error---"
            $outputString | Should -Match "Exception Message:"
        }

        It "Should include HTTP status code when available" {
            # Create a mock response with status code
            $mockResponse = New-Object System.Net.HttpWebResponse
            $exception = [System.Net.WebException]::new(
                "The remote server returned an error: (401) Unauthorized.",
                $null,
                [System.Net.WebExceptionStatus]::ProtocolError,
                $mockResponse
            )

            Mock Invoke-WebRequest {
                throw $exception
            }

            $output = & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "invalid-key" `
                -TargetEnvironmentAlias "Development" `
                -PipelineVendor "TESTRUN" 6>&1 2>&1

            $outputString = $output -join "`n"
            $outputString | Should -Match "---Error---"
            $outputString | Should -Match "Exception Message:.*Unauthorized"
        }
    }
}
