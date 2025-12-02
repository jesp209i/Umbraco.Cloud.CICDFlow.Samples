BeforeAll {
    $ScriptPath = Join-Path $PSScriptRoot "..\..\powershell\Test-DeploymentStatus.ps1"
}

Describe "Test-DeploymentStatus" {
    Context "When deployment completes successfully" {
        BeforeAll {
            $mockResponse = @{
                StatusCode = 200
                Content = @{
                    deploymentState = "Completed"
                    modifiedUtc = "2024-01-01T00:00:00Z"
                    deploymentStatusMessages = @()
                } | ConvertTo-Json
            }
        }

        It "Should exit successfully when deployment completes" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]$mockResponse
            }
            Mock Start-Sleep { }

            & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -DeploymentId "deployment-123" `
                -TimeoutSeconds 60

            # If we get here without exception, the test passes
            $true | Should -Be $true
        }

        It "Should output deployment status messages" {
            $mockWithMessages = @{
                StatusCode = 200
                Content = @{
                    deploymentState = "Completed"
                    modifiedUtc = "2024-01-01T00:00:00Z"
                    deploymentStatusMessages = @(
                        @{ timestampUtc = "2024-01-01T00:00:00Z"; message = "Build started" }
                        @{ timestampUtc = "2024-01-01T00:01:00Z"; message = "Build completed" }
                    )
                } | ConvertTo-Json -Depth 3
            }

            Mock Invoke-WebRequest {
                return [PSCustomObject]$mockWithMessages
            }
            Mock Start-Sleep { }

            $output = & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -DeploymentId "deployment-123" `
                -TimeoutSeconds 60 6>&1

            $outputString = $output -join "`n"
            $outputString | Should -Match "Build started"
        }

        It "Should output success message" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]$mockResponse
            }
            Mock Start-Sleep { }

            $output = & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -DeploymentId "deployment-123" `
                -TimeoutSeconds 60 6>&1

            $outputString = $output -join "`n"
            $outputString | Should -Match "Deployment completed successfully"
        }
    }

    Context "When deployment fails" {
        BeforeAll {
            $mockFailedResponse = @{
                StatusCode = 200
                Content = @{
                    deploymentState = "Failed"
                    modifiedUtc = "2024-01-01T00:00:00Z"
                    deploymentStatusMessages = @()
                } | ConvertTo-Json
            }
        }

        It "Should output failure message" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]$mockFailedResponse
            }
            Mock Start-Sleep { }

            $output = & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -DeploymentId "deployment-123" `
                -TimeoutSeconds 60 6>&1 2>&1

            $outputString = $output -join "`n"
            $outputString | Should -Match "Deployment Failed"
        }
    }

    Context "When polling for status" {
        It "Should poll until deployment completes" {
            Mock Invoke-WebRequest {
                $countFile = Join-Path $TestDrive "poll_count.txt"
                if (Test-Path $countFile) {
                    $count = [int](Get-Content $countFile)
                } else {
                    $count = 0
                }
                $count++
                Set-Content -Path $countFile -Value $count

                if ($count -lt 3) {
                    return [PSCustomObject]@{
                        StatusCode = 200
                        Content = @{
                            deploymentState = "InProgress"
                            modifiedUtc = "2024-01-01T00:00:00Z"
                            deploymentStatusMessages = @()
                        } | ConvertTo-Json
                    }
                } else {
                    return [PSCustomObject]@{
                        StatusCode = 200
                        Content = @{
                            deploymentState = "Completed"
                            modifiedUtc = "2024-01-01T00:00:00Z"
                            deploymentStatusMessages = @()
                        } | ConvertTo-Json
                    }
                }
            }
            Mock Start-Sleep { }

            & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -DeploymentId "deployment-123" `
                -TimeoutSeconds 60

            Should -Invoke Invoke-WebRequest -Times 3 -Exactly
        }

        It "Should handle Pending status" {
            Mock Invoke-WebRequest {
                # Use a file to track call count across mock invocations
                $countFile = Join-Path $TestDrive "pending_count.txt"
                if (Test-Path $countFile) {
                    $count = [int](Get-Content $countFile)
                } else {
                    $count = 0
                }
                $count++
                Set-Content -Path $countFile -Value $count

                if ($count -eq 1) {
                    return [PSCustomObject]@{
                        StatusCode = 200
                        Content = @{
                            deploymentState = "Pending"
                            modifiedUtc = "2024-01-01T00:00:00Z"
                            deploymentStatusMessages = @()
                        } | ConvertTo-Json
                    }
                } else {
                    return [PSCustomObject]@{
                        StatusCode = 200
                        Content = @{
                            deploymentState = "Completed"
                            modifiedUtc = "2024-01-01T00:00:00Z"
                            deploymentStatusMessages = @()
                        } | ConvertTo-Json
                    }
                }
            }
            Mock Start-Sleep { }

            & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -DeploymentId "deployment-123" `
                -TimeoutSeconds 60

            Should -Invoke Invoke-WebRequest -Times 2 -Exactly
        }

        It "Should handle Queued status" {
            Mock Invoke-WebRequest {
                $countFile = Join-Path $TestDrive "queued_count.txt"
                if (Test-Path $countFile) {
                    $count = [int](Get-Content $countFile)
                } else {
                    $count = 0
                }
                $count++
                Set-Content -Path $countFile -Value $count

                if ($count -eq 1) {
                    return [PSCustomObject]@{
                        StatusCode = 200
                        Content = @{
                            deploymentState = "Queued"
                            modifiedUtc = "2024-01-01T00:00:00Z"
                            deploymentStatusMessages = @()
                        } | ConvertTo-Json
                    }
                } else {
                    return [PSCustomObject]@{
                        StatusCode = 200
                        Content = @{
                            deploymentState = "Completed"
                            modifiedUtc = "2024-01-01T00:00:00Z"
                            deploymentStatusMessages = @()
                        } | ConvertTo-Json
                    }
                }
            }
            Mock Start-Sleep { }

            & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -DeploymentId "deployment-123" `
                -TimeoutSeconds 60

            Should -Invoke Invoke-WebRequest -Times 2 -Exactly
        }
    }

    Context "When using custom BaseUrl" {
        It "Should use custom BaseUrl when provided" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]@{
                    StatusCode = 200
                    Content = @{
                        deploymentState = "Completed"
                        modifiedUtc = "2024-01-01T00:00:00Z"
                        deploymentStatusMessages = @()
                    } | ConvertTo-Json
                }
            } -Verifiable
            Mock Start-Sleep { }

            & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -DeploymentId "deployment-123" `
                -TimeoutSeconds 60 `
                -BaseUrl "https://custom.api.com"

            Should -Invoke Invoke-WebRequest -ParameterFilter {
                $URI -like "https://custom.api.com/*"
            }
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
                -TimeoutSeconds 60 6>&1 2>&1

            $outputString = $output -join "`n"
            $outputString | Should -Match "---Error---"
        }
    }

    Context "When deployment has unexpected status" {
        It "Should output error for unexpected status" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]@{
                    StatusCode = 200
                    Content = @{
                        deploymentState = "Unknown"
                        modifiedUtc = "2024-01-01T00:00:00Z"
                        deploymentStatusMessages = @()
                    } | ConvertTo-Json
                }
            }
            Mock Start-Sleep { }

            $output = & $ScriptPath `
                -ProjectId "test-project" `
                -ApiKey "test-api-key" `
                -DeploymentId "deployment-123" `
                -TimeoutSeconds 60 6>&1 2>&1

            $outputString = $output -join "`n"
            $outputString | Should -Match "Unexpected status"
        }
    }
}
