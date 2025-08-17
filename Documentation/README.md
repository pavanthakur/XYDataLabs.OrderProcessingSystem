# Documentation Organization

This folder contains all project documentation files that were previously scattered in the root directory. The files have been organized into logical categories for better navigation and maintenance.

## 📁 Folder Structure

### 01-Project-Overview
Contains main project documentation and overview files:
- `README.md` - Main project documentation
- `CLEANUP_SUMMARY.md` - Project cleanup activities summary

### 02-Docker-Guides
Contains Docker-related setup and configuration guides:
- `DOCKER_COMPREHENSIVE_GUIDE.md` - Complete Docker setup guide (46KB)
- `ENTERPRISE_DOCKER_GUIDE.md` - Enterprise Docker configuration (17KB)
- `VISUAL_STUDIO_DOCKER_PROFILES.md` - Visual Studio Docker profiles guide (12KB)

### 03-Database-Guides
*Currently empty - reserved for database-related documentation*

### 04-Configuration-Guides
Contains application configuration and settings documentation:
- `SIMPLIFIED_CONFIG_GUIDE.md` - Simplified configuration guide (7KB)
- `DOTENV_DEPENDENCY_ELIMINATION_SUMMARY.md` - Environment configuration summary (8KB)

### 05-Enterprise-Architecture
*Currently empty - reserved for enterprise architecture documentation*

### 06-Testing-and-Results
*Currently empty - reserved for testing documentation and results*

## �️ Resources Folder Organization

The project has been reorganized with a centralized **Resources** folder containing:

### Resources/BuildConfiguration
- `BannedSymbols.txt` - Code analysis banned symbols
- `CodeAnalysis.ruleset` - Static code analysis rules
- `Directory.Build.props` - MSBuild global properties
- `Directory.Packages.props` - Package management configuration

### Resources/Configuration
- `sharedsettings.dev.json` - Development environment settings
- `sharedsettings.uat.json` - UAT environment settings
- `sharedsettings.prod.json` - Production environment settings
- `sharedsettings.local.json` - Local development overrides

### Resources/Docker
- `start-docker.ps1` - Main Docker startup script with enterprise features
- `docker-compose.dev.yml` - Development environment composition
- `docker-compose.uat.yml` - UAT environment composition
- `docker-compose.prod.yml` - Production environment composition
- `docker-compose.database.yml` - Database services composition

### Resources/Certificates
- SSL certificates for HTTPS development and testing

## �📋 Organization Summary

**Files with Content (6 files):**
- Project Overview: 2 files with content 
- Docker Guides: 3 files (all with substantial content - 75KB total)
- Configuration Guides: 2 files (15KB total)

**Resources Structure:**
- Build Configuration: 4 files for MSBuild and code analysis
- Configuration: 4 environment-specific settings files
- Docker: 1 script + 4 compose files for multi-environment deployment
- Certificates: SSL/TLS certificates for secure development

## 🔄 Path Updates

**Important:** The project structure has been reorganized. Key script locations:
- **Docker Script:** `Resources\Docker\start-docker.ps1` (moved from root)
- **Configuration:** `Resources\Configuration\sharedsettings.*.json`
- **Build Files:** `Resources\BuildConfiguration\*`

## 🔄 Maintenance

This organization makes it easier to:
- Find relevant documentation quickly
- Identify gaps in documentation (empty folders)
- Maintain and update related documents together
- Keep the root directory clean and organized
- Centralize all resources in logical subfolders
- Maintain consistent build and deployment configurations

## 📝 Next Steps

Consider:
1. Populating empty categories with relevant documentation
2. Creating index files for each category if they grow larger
3. Adding new documentation files to appropriate categories
4. Keeping the folder structure aligned with Visual Studio solution
