Describe 'Repository quality' {
    BeforeAll {
        $repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    }

    It 'contains PowerShell scripts' {
        @(Get-ChildItem -Path $repositoryRoot -Recurse -Filter *.ps1).Count | Should -BeGreaterThan 0
    }

    It 'contains no empty PowerShell scripts' {
        $empty = Get-ChildItem -Path $repositoryRoot -Recurse -Filter *.ps1 | Where-Object Length -eq 0
        $empty | Should -BeNullOrEmpty
    }
}
