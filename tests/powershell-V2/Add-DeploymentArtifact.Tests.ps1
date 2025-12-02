BeforeAll {
    $ScriptPath = Join-Path $PSScriptRoot "..\..\V2\powershell\Add-DeploymentArtifact.ps1"
}

Describe "Add-DeploymentArtifact" {
    BeforeEach {
        $env:GITHUB_OUTPUT = Join-Path $TestDrive "github_output.txt"
        New-Item -Path $env:GITHUB_OUTPUT -ItemType File -Force | Out-Null

        # Create a test artifact file
        $script:TestArtifactFile = Join-Path $TestDrive "artifact.zip"
        Set-Content -Path $script:TestArtifactFile -Value "mock artifact content"
    }

    AfterEach {
        Remove-Item -Path $env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
    }

    Context "When FilePath is empty" {
        It "Should exit with error when FilePath is empty" {
            $result = pwsh -Command "& '$ScriptPath' -ProjectId 'test' -ApiKey 'key' -FilePath '' -PipelineVendor 'GITHUB'; exit `$LASTEXITCODE" 2>&1
            $LASTEXITCODE | Should -Be 1
            $result | Should -Contain "FilePath is empty"
        }
    }

    Context "When file does not exist" {
        It "Should exit with error when file does not exist" {
            $result = pwsh -Command "& '$ScriptPath' -ProjectId 'test' -ApiKey 'key' -FilePath '/nonexistent/file.zip' -PipelineVendor 'GITHUB'; exit `$LASTEXITCODE" 2>&1
            $LASTEXITCODE | Should -Be 1
            $result | Should -Contain "FilePath does not contain a file"
        }
    }

    Context "When artifact upload succeeds" {
        BeforeAll {
            $mockArtifactId = "artifact-12345-abcde"
            $mockResponse = @{
                StatusCode = 200
                Content = @{ artifactId = $mockArtifactId } | ConvertTo-Json
            }
        }

        It "Should return artifact ID for GITHUB vendor" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]$mockResponse
            }

            & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -FilePath $script:TestArtifactFile `
                -Description "Test artifact" `
                -Version "1.0.0" `
                -PipelineVendor "GITHUB"

            $output = Get-Content $env:GITHUB_OUTPUT
            $output | Should -Contain "artifactId=$mockArtifactId"
        }

        It "Should output Azure DevOps variable format" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]$mockResponse
            }

            $output = & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -FilePath $script:TestArtifactFile `
                -Description "Test artifact" `
                -Version "1.0.0" `
                -PipelineVendor "AZUREDEVOPS" 6>&1

            $vsoOutput = $output | Where-Object { $_ -match "##vso\[task\.setvariable" }
            $vsoOutput | Should -Not -BeNullOrEmpty
            $vsoOutput[0] | Should -BeLike "*artifactId*$mockArtifactId*"
        }

        It "Should output success message" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]$mockResponse
            }

            $output = & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -FilePath $script:TestArtifactFile `
                -Description "Test artifact" `
                -Version "1.0.0" `
                -PipelineVendor "TESTRUN" 6>&1

            $outputString = $output -join "`n"
            $outputString | Should -Match "Artifact uploaded"
        }
    }

    Context "When using custom BaseUrl" {
        It "Should use custom BaseUrl when provided" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]@{
                    StatusCode = 200
                    Content = '{"artifactId":"test-id"}'
                }
            } -Verifiable

            & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -FilePath $script:TestArtifactFile `
                -PipelineVendor "TESTRUN" `
                -BaseUrl "https://custom.api.com"

            Should -Invoke Invoke-WebRequest -ParameterFilter {
                $Uri -like "https://custom.api.com/*"
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
        It "Should have error handling in catch block" {
            $scriptContent = Get-Content $ScriptPath -Raw
            $scriptContent | Should -Match 'catch'
            $scriptContent | Should -Match '---Error---'
            $scriptContent | Should -Match 'exit 1'
        }

        It "Should output error marker on failure" {
            Mock Invoke-WebRequest {
                throw [System.Net.WebException]::new("Connection refused")
            }

            $output = & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -FilePath $script:TestArtifactFile `
                -PipelineVendor "TESTRUN" 6>&1 2>&1

            $outputString = $output -join "`n"
            $outputString | Should -Match "---Error---"
        }
    }
}
