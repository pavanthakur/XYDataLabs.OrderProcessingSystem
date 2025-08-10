# Docker Port Allocation Guide

## New Port Allocation Scheme (5020 Series)

Each environment now has completely unique ports to allow simultaneous running of multiple environments without conflicts.

### Port Ranges by Environment

| Environment | API HTTP | API HTTPS | UI HTTP | UI HTTPS | Range    |
|-------------|----------|-----------|---------|----------|----------|
| **local**   | 5010     | 5011      | 5012    | 5013     | 5010-5019|
| **dev**     | 5020     | 5021      | 5022    | 5023     | 5020-5029|
| **uat**     | 5030     | 5031      | 5032    | 5033     | 5030-5039|
| **prod**    | 5040     | 5041      | 5042    | 5043     | 5040-5049|

### Environment Access URLs

#### Local Environment
- **API HTTP**: http://localhost:5010/swagger
- **API HTTPS**: https://localhost:5011/swagger
- **UI HTTP**: http://localhost:5012
- **UI HTTPS**: https://localhost:5013

#### Development Environment
- **API HTTP**: http://localhost:5020/swagger
- **API HTTPS**: https://localhost:5021/swagger
- **UI HTTP**: http://localhost:5022
- **UI HTTPS**: https://localhost:5023

#### UAT Environment
- **API HTTP**: http://localhost:5030/swagger
- **API HTTPS**: https://localhost:5031/swagger
- **UI HTTP**: http://localhost:5032
- **UI HTTPS**: https://localhost:5033

#### Production Environment
- **API HTTP**: http://localhost:5040/swagger
- **API HTTPS**: https://localhost:5041/swagger
- **UI HTTP**: http://localhost:5042
- **UI HTTPS**: https://localhost:5043

### Benefits of New Port Allocation

1. **Simultaneous Environments**: Run local, dev, uat, and prod simultaneously without port conflicts
2. **Clear Separation**: Each environment has its dedicated port range
3. **Easy Identification**: Port number indicates environment (10=local, 20=dev, 30=uat, 40=prod)
4. **Future Expansion**: Room for additional services in each environment's range
5. **Developer Friendly**: No need to stop one environment to test another

### Usage Examples

```powershell
# Start all environments simultaneously
.\start-docker.ps1 -Environment local -Profile http  # Uses ports 5010-5013
.\start-docker.ps1 -Environment dev -Profile http    # Uses ports 5020-5023
.\start-docker.ps1 -Environment uat -Profile http    # Uses ports 5030-5033
.\start-docker.ps1 -Environment prod -Profile http   # Uses ports 5040-5043

# Access different environments
# Local API: http://localhost:5010/swagger
# Dev API: http://localhost:5020/swagger
# UAT API: http://localhost:5030/swagger
# Prod API: http://localhost:5040/swagger
```

### Migration Notes

- **Old ports (5000-5003)**: No longer used, containers should be stopped and removed
- **Configuration files**: All sharedsettings.*.json files updated with new ports
- **Launch settings**: Environment variables updated to reflect new port assignments
- **Docker compose**: Automatic port extraction from sharedsettings files

### Port Conflict Resolution

If any of these ports are already in use on your system:

1. Check what's using the port: `netstat -ano | findstr :5020`
2. Stop the conflicting service or change our port range
3. Update the corresponding sharedsettings.{env}.json file
4. Restart the Docker environment

### Future Port Allocation

Reserved ranges for future expansion:

- **5050-5059**: Reserved for staging environment
- **5060-5069**: Reserved for integration testing
- **5070-5079**: Reserved for performance testing
- **5080-5089**: Reserved for additional services
