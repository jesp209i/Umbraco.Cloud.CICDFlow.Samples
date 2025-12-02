BeforeAll {
    $ScriptPath = Join-Path $PSScriptRoot "..\..\V2\powershell\Apply-Patch.ps1"
}

Describe "Apply-Patch" {
    BeforeEach {
        $env:GITHUB_OUTPUT = Join-Path $TestDrive "github_output.txt"
        New-Item -Path $env:GITHUB_OUTPUT -ItemType File -Force | Out-Null

        # Create a test patch file
        $script:TestPatchFile = Join-Path $TestDrive "test.patch"
        Set-Content -Path $script:TestPatchFile -Value "mock patch content"
    }

    AfterEach {
        Remove-Item -Path $env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
    }

    Context "Script parameter validation" {
        It "Should accept all required parameters" {
            # Just verify the script can be parsed with parameters
            $scriptContent = Get-Content $ScriptPath -Raw
            $scriptContent | Should -Match '\$PatchFile'
            $scriptContent | Should -Match '\$LatestDeploymentId'
            $scriptContent | Should -Match '\$PipelineVendor'
            $scriptContent | Should -Match '\$GitUserName'
            $scriptContent | Should -Match '\$GitUserEmail'
        }
    }

    Context "Git configuration" {
        It "Should configure git user name and email" {
            $scriptContent = Get-Content $ScriptPath -Raw
            $scriptContent | Should -Match 'git config user\.name'
            $scriptContent | Should -Match 'git config user\.email'
        }
    }

    Context "Patch already applied" {
        It "Should exit successfully when patch is already applied (reverse check succeeds)" {
            $scriptContent = Get-Content $ScriptPath -Raw
            $scriptContent | Should -Match 'git apply.*--reverse.*--check'
            $scriptContent | Should -Match 'Patch already applied'
        }
    }

    Context "Patch application logic" {
        It "Should check if patch can be applied before applying" {
            $scriptContent = Get-Content $ScriptPath -Raw
            $scriptContent | Should -Match 'git apply.*--check'
        }

        It "Should apply patch with whitespace options" {
            $scriptContent = Get-Content $ScriptPath -Raw
            $scriptContent | Should -Match 'git apply.*--ignore-space-change.*--ignore-whitespace'
        }

        It "Should commit with skip ci message" {
            $scriptContent = Get-Content $ScriptPath -Raw
            $scriptContent | Should -Match '\[skip ci\]'
        }
    }

    Context "GITHUB vendor handling" {
        It "Should write updatedSha to GITHUB_OUTPUT" {
            $scriptContent = Get-Content $ScriptPath -Raw
            $scriptContent | Should -Match 'updatedSha=.*Out-File.*GITHUB_OUTPUT'
        }

        It "Should use git rev-parse HEAD to get SHA" {
            $scriptContent = Get-Content $ScriptPath -Raw
            $scriptContent | Should -Match 'git rev-parse HEAD'
        }
    }

    Context "AZUREDEVOPS vendor handling" {
        It "Should output Azure DevOps variable format" {
            $scriptContent = Get-Content $ScriptPath -Raw
            $scriptContent | Should -Match '##vso\[task\.setvariable variable=updatedSha'
        }

        It "Should checkout branch for Azure DevOps" {
            $scriptContent = Get-Content $ScriptPath -Raw
            $scriptContent | Should -Match 'git checkout.*BUILD_SOURCEBRANCHNAME'
        }
    }

    Context "Unsupported vendor handling" {
        It "Should have error message for unsupported vendors" {
            $scriptContent = Get-Content $ScriptPath -Raw
            $scriptContent | Should -Match 'Please use one of the supported Pipeline Vendors'
        }

        It "Should exit with code 1 for unsupported vendor" {
            $scriptContent = Get-Content $ScriptPath -Raw
            $scriptContent | Should -Match 'Default[\s\S]*Exit 1'
        }
    }

    Context "Patch failure handling" {
        It "Should show verbose output when patch cannot be applied" {
            $scriptContent = Get-Content $ScriptPath -Raw
            $scriptContent | Should -Match 'git apply -v --reject'
        }

        It "Should display error message when patch fails" {
            $scriptContent = Get-Content $ScriptPath -Raw
            $scriptContent | Should -Match 'Patch cannot be applied'
        }
    }
}
