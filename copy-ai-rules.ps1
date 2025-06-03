# Version: 1.0.0

<#
.SYNOPSIS
    Copies AI rules from .ai-rules/*.md to Cursor, GitHub Copilot and Junie instruction folders with appropriate headers.

.DESCRIPTION
    This script processes markdown files in the .ai-rules folder and copies them to:
    - .cursor/rules/*.mdc (with Cursor-specific YAML header)
    - .github/instructions/*.instructions.md (with Copilot-specific YAML header)  
    - .junie/guidelines.md (combined content without front matter)
    
    The script uses an optional ai-rules-config.json file to control which assistants
    to generate rules for. If the config file doesn't exist, rules are generated for all assistants.

    Example config file:
    {
        "assistants": ["cursor", "copilot"]
    }

.EXAMPLE
    ./copy-ai-rules.ps1
#>

# Ensure we're using cross-platform path separators
$PathSeparator = [System.IO.Path]::DirectorySeparatorChar

# Define source and target directories
$SourceDir = ".ai-rules"
$ConfigFile = Join-Path $SourceDir "ai-rules-config.json"
$CursorDir = ".cursor" + $PathSeparator + "rules"
$CopilotDir = ".github" + $PathSeparator + "instructions"
$JunieDir = ".junie"

# Function to check for updates
function Test-ScriptUpdate {
    param([string]$ScriptPath)

    try {
        $currentVersion = "1.0.0"  # fallback
        if ($ScriptPath -and (Test-Path $ScriptPath)) {
            $scriptContent = Get-Content $ScriptPath | Select-Object -First 10 | Out-String
            if ($scriptContent -match "# Version: ([\d\.]+)") {
                $currentVersion = $matches[1]
            }
        }

        $rawUrl = "https://raw.githubusercontent.com/Kros-sk/copy-ai-rules/refs/heads/master/copy-ai-rules.ps1"
        $content = Invoke-RestMethod -Uri $rawUrl -TimeoutSec 5 -ErrorAction Stop
        
        if ($content -match "# Version: ([\d\.]+)") {
            $latestVersion = $matches[1]
            
            if ([version]$latestVersion -gt [version]$CurrentVersion) {
                Write-Host ""
                Write-Host "🚫 Script Update Required!" -ForegroundColor Red
                Write-Host "   Current version: v$CurrentVersion" -ForegroundColor Yellow
                Write-Host "   Latest version:  v$latestVersion" -ForegroundColor Green
                Write-Host ""
                Write-Host "Please update to the latest version before continuing:" -ForegroundColor White
                Write-Host "   Download: https://github.com/Kros-sk/copy-ai-rules" -ForegroundColor Blue
                Write-Host ""
                Write-Host "Aborting script execution." -ForegroundColor Red
                return $false
            }
        }
        
        return $true
    }
    catch {
        # If version check fails, allow script to continue
        Write-Debug "Version check failed: $($_.Exception.Message)"
        return $true
    }
}


# Function to read configuration file
function Get-AssistantConfig {
    param([string]$ConfigPath)
    
    # Default configuration if file doesn't exist
    $defaultConfig = @("cursor", "copilot", "junie")
    
    if (-not (Test-Path $ConfigPath)) {
        Write-Host "Config file not found. Using default assistants: $($defaultConfig -join ', ')" -ForegroundColor Yellow
        return $defaultConfig
    }
    
    try {
        $configContent = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
        $config = $configContent | ConvertFrom-Json
        
        if ($config.assistants -and $config.assistants.Count -gt 0) {
            $supportedAssistants = @("cursor", "copilot", "junie")
            $validAssistants = $config.assistants | Where-Object { $_ -in $supportedAssistants }
            
            if ($validAssistants.Count -eq 0) {
                Write-Warning "No valid assistants found in config. Using defaults: $($defaultConfig -join ', ')"
                return $defaultConfig
            }
            
            Write-Host "Loaded configuration. Assistants: $($validAssistants -join ', ')" -ForegroundColor Cyan
            return $validAssistants
        } else {
            Write-Warning "Invalid config format. Using defaults: $($defaultConfig -join ', ')"
            return $defaultConfig
        }
    }
    catch {
        Write-Error "Failed to parse config file: $($_.Exception.Message)"
        Write-Host "Using default assistants: $($defaultConfig -join ', ')" -ForegroundColor Yellow
        return $defaultConfig
    }
}

# Function to parse existing YAML front matter
function Get-YamlFrontMatter {
    param([string]$Content)
    
    $frontMatter = @{}
    $lines = $Content -split "`n"
    
    if ($lines[0].Trim() -eq "---") {
        $endIndex = -1
        for ($i = 1; $i -lt $lines.Length; $i++) {
            if ($lines[$i].Trim() -eq "---") {
                $endIndex = $i
                break
            }
        }
        
        if ($endIndex -gt 0) {
            for ($i = 1; $i -lt $endIndex; $i++) {
                $line = $lines[$i].Trim()
                if ($line -and $line.Contains(":")) {
                    $parts = $line -split ":", 2
                    $key = $parts[0].Trim()
                    $value = $parts[1].Trim().Trim('"', "'")
                    $frontMatter[$key] = $value
                }
            }
            
            # Return front matter and content without YAML
            $contentWithoutYaml = ($lines[($endIndex + 1)..($lines.Length - 1)] -join "`n").Trim()
            return @{
                FrontMatter = $frontMatter
                Content = $contentWithoutYaml
            }
        }
    }
    
    # No front matter found, return original content
    return @{
        FrontMatter = @{}
        Content = $Content.Trim()
    }
}

# Function to create Cursor header
function New-CursorHeader {
    param(
        [hashtable]$FrontMatter,
        [string]$FileName
    )
    
    $description = if ($FrontMatter.ContainsKey("description")) { 
        $FrontMatter["description"] 
    } else { 
        "Generated from $FileName" 
    }
    
    $pattern = if ($FrontMatter.ContainsKey("globs")) { 
        $FrontMatter["globs"] 
    } else { 
        "**/*.cs" 
    }
    
    # Remove quotes from pattern for Cursor
    $pattern = $pattern.Trim('"', "'")
    
    # Auto-detect globs and alwaysApply based on pattern
    if ($pattern -eq "**") {
        # Apply to all files - empty globs with alwaysApply true
        $globs = ""
        $alwaysApply = "true"
    } else {
        # Specific pattern - use globs with alwaysApply false
        $globs = $pattern
        $alwaysApply = "false"
    }
    
    return @"
---
# Generated file - do not edit directly, use .ai-rules instead
description: $description
globs: $globs
alwaysApply: $alwaysApply
---

"@
}

# Function to create Copilot header
function New-CopilotHeader {
    param(
        [hashtable]$FrontMatter,
        [string]$FileName
    )
    
    $pattern = if ($FrontMatter.ContainsKey("globs")) {
        $FrontMatter["globs"]
    } else { 
        "**/*.cs" 
    }
    
    # Always add quotes for Copilot (YAML parser strips them from source)
    return @"
---
# Generated file - do not edit directly! Use .ai-rules instead
applyTo: '$pattern'
---

"@
}

# Main script execution
try {
    Write-Host "AI Rules Copy Script" -ForegroundColor Green
    
    # Check for updates and abort if newer version available
    if (-not (Test-ScriptUpdate -ScriptPath $MyInvocation.MyCommand.Path)) {
        exit 1
    }

    Write-Host "Starting AI Rules copy process..." -ForegroundColor Green
    
    # Load configuration
    $enabledAssistants = Get-AssistantConfig -ConfigPath $ConfigFile
    $generateCursor = "cursor" -in $enabledAssistants
    $generateCopilot = "copilot" -in $enabledAssistants
    $generateJunie = "junie" -in $enabledAssistants
    
    # Check if source directory exists
    if (-not (Test-Path $SourceDir)) {
        Write-Error "Source directory '$SourceDir' not found!"
        exit 1
    }

    # Clean up existing target directories to start fresh
    Write-Host "Cleaning up existing target directories..." -ForegroundColor Yellow
    
    if (Test-Path $CursorDir) {
        Remove-Item -Path $CursorDir -Recurse -Force
        Write-Host "  → Removed: $CursorDir" -ForegroundColor Gray
    }
    
    if (Test-Path $CopilotDir) {
        Remove-Item -Path $CopilotDir -Recurse -Force
        Write-Host "  → Removed: $CopilotDir" -ForegroundColor Gray
    }
    
    if (Test-Path $JunieDir) {
        Remove-Item -Path $JunieDir -Recurse -Force
        Write-Host "  → Removed: $JunieDir" -ForegroundColor Gray
    }
    
    # Create target directories if they don't exist and are needed
    if ($generateCursor -and -not (Test-Path $CursorDir)) {
        New-Item -Path $CursorDir -ItemType Directory -Force | Out-Null
        Write-Host "Created directory: $CursorDir" -ForegroundColor Yellow
    }
    
    if ($generateCopilot -and -not (Test-Path $CopilotDir)) {
        New-Item -Path $CopilotDir -ItemType Directory -Force | Out-Null
        Write-Host "Created directory: $CopilotDir" -ForegroundColor Yellow
    }
    
    if ($generateJunie -and -not (Test-Path $JunieDir)) {
        New-Item -Path $JunieDir -ItemType Directory -Force | Out-Null
        Write-Host "Created directory: $JunieDir" -ForegroundColor Yellow
    }
    
    # Initialize Junie content collection
    $junieContent = @()
    
    # Get all .md files from source directory
    $mdFiles = Get-ChildItem -Path $SourceDir -Filter "*.md" -File | Where-Object { $_.Name -ne "README.md" }
    
    if ($mdFiles.Count -eq 0) {
        Write-Warning "No .md files found in '$SourceDir' directory."
        exit 0
    }
    
    Write-Host "Found $($mdFiles.Count) markdown file(s) to process." -ForegroundColor Cyan
    $filesProcessed = 0
    
    foreach ($file in $mdFiles) {
        Write-Host "Processing: $($file.Name)" -ForegroundColor White
        
        # Read file content
        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
        
        # Parse existing front matter
        $parsed = Get-YamlFrontMatter -Content $content
        
        # Generate base filename without extension
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        
        # Create Cursor file if enabled
        if ($generateCursor) {
            $cursorFileName = $baseName + ".mdc"
            $cursorFilePath = Join-Path $CursorDir $cursorFileName
            $cursorHeader = New-CursorHeader -FrontMatter $parsed.FrontMatter -FileName $file.Name
            $cursorContent = $cursorHeader + $parsed.Content
            
            Set-Content -Path $cursorFilePath -Value $cursorContent -Encoding UTF8
            Write-Host "  → Created: $cursorFilePath" -ForegroundColor Green
        }
        
        # Create Copilot file if enabled
        if ($generateCopilot) {
            $copilotFileName = $baseName + ".instructions.md"
            $copilotFilePath = Join-Path $CopilotDir $copilotFileName
            $copilotHeader = New-CopilotHeader -FrontMatter $parsed.FrontMatter -FileName $file.Name
            $copilotContent = $copilotHeader + $parsed.Content
            
            Set-Content -Path $copilotFilePath -Value $copilotContent -Encoding UTF8
            Write-Host "  → Created: $copilotFilePath" -ForegroundColor Green
        }
        
        # Collect content for Junie if enabled
        if ($generateJunie) {
            # Add a section header for this rule file
            $junieContent += "# $($file.BaseName)"
            $junieContent += ""
            $junieContent += $parsed.Content
            $junieContent += ""
            $junieContent += "---"
            $junieContent += ""
        }
        
        $filesProcessed++
    }
    
    # Create Junie combined file if enabled
    if ($generateJunie -and $junieContent.Count -gt 0) {
        $junieFilePath = Join-Path $JunieDir "guidelines.md"
        # Remove the last separator
        if ($junieContent[-2] -eq "---") {
            $junieContent = $junieContent[0..($junieContent.Count - 3)]
        }
        $junieCombinedContent = $junieContent -join "`n"
        
        Set-Content -Path $junieFilePath -Value $junieCombinedContent -Encoding UTF8
        Write-Host "  → Created: $junieFilePath (combined from $filesProcessed files)" -ForegroundColor Green
    }
    
    Write-Host "AI Rules copy process completed successfully!" -ForegroundColor Green
    Write-Host "Processed $filesProcessed files for assistants: $($enabledAssistants -join ', ')" -ForegroundColor Cyan
}
catch {
    Write-Error "An error occurred: $($_.Exception.Message)"
    exit 1
}