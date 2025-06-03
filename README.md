# AI Rules Copy Script

A cross-platform PowerShell script that converts your AI coding rules into assistant-specific formats. Write once, deploy everywhere.

## 🚀 Quick Start

```bash
# Download and run the script from the project root
curl -o copy-ai-rules.ps1 https://raw.githubusercontent.com/Kros-sk/copy-ai-rules/main/copy-ai-rules.ps1
pwsh ./copy-ai-rules.ps1
```

## 📁 Setup

Create this folder structure in your project:

```
your-project/
├── .ai-rules/
│   ├── api-rules.md
│   ├── domain-rules.md
│   ├── ai-rules-config.json
│   └── README.md              # ← Instructions for your team (ignored by script)
└── copy-ai-rules.ps1
```

## ✍️ Writing Rules

Create `.md` files in `.ai-rules/` with this format:

```yaml
---
description: API layer coding standards
globs: "**/Api/**/*.cs"
---

# API Rules

- Use async/await for all API endpoints
- Always validate input parameters
- Return consistent error responses
```

## ⚙️ Configuration

Control which assistants to generate for in `.ai-rules/ai-rules-config.json`:

```json
{
  "assistants": ["cursor", "copilot", "junie"]
}
```

## 🤖 Supported AI Assistants

| Assistant | Output Location | Format |
|-----------|----------------|---------|
| **Cursor** | `.cursor/rules/*.mdc` | Individual files with YAML headers |
| **GitHub Copilot** | `.github/instructions/*.instructions.md` | Individual files with YAML headers |
| **Junie** | `.junie/guidelines.md` | Single combined file |

## 🔄 Auto-Updates

The script automatically checks for updates and requires you to use the latest version. This ensures everyone on your team uses the same features.

## 💡 Example Output

**Input:** `.ai-rules/api-rules.md`
```yaml
---
description: API guidelines  
globs: "**/Controllers/**/*.cs"
---

Use dependency injection for all services.
```

**Generated for Cursor:** `.cursor/rules/api-rules.mdc`
```yaml
---
description: API guidelines
globs: **/Controllers/**/*.cs
alwaysApply: false
---

Use dependency injection for all services.
```

**Generated for Copilot:** `.github/instructions/api-rules.instructions.md`
```yaml
---
applyTo: '**/Controllers/**/*.cs'
---

Use dependency injection for all services.
```

## 🛠️ Requirements

- PowerShell 7+ (cross-platform)
- Internet connection (for update checks)

## 📝 License

MIT License - feel free to use in any project!