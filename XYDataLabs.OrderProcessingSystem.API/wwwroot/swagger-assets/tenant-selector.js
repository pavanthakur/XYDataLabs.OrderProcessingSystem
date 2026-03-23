(function () {
    const tenantStorageKey = 'order-processing:selected-tenant';
    const runtimeConfigurationUrl = '/api/v1/info/runtime-configuration';
    // Security scheme key must match options.AddSecurityDefinition("TenantCode", ...) in Program.cs
    const securityDefinitionKey = 'TenantCode';
    let selectedTenantCode = null;
    let availableTenants = [];

    const getStoredTenantCode = () => {
        try {
            return window.localStorage.getItem(tenantStorageKey);
        } catch (error) {
            console.warn('Unable to read stored Swagger tenant selection.', error);
            return null;
        }
    };

    const persistTenantCode = tenantCode => {
        try {
            if (!tenantCode) {
                window.localStorage.removeItem(tenantStorageKey);
                return;
            }

            window.localStorage.setItem(tenantStorageKey, tenantCode);
        } catch (error) {
            console.warn('Unable to persist Swagger tenant selection.', error);
        }
    };

    const authorizeWithTenant = tenantCode => {
        if (!tenantCode || !window.ui?.preauthorizeApiKey) {
            return;
        }

        window.ui.preauthorizeApiKey(securityDefinitionKey, tenantCode);
    };

    const resolveTenantCode = (payload, preferredTenantCode) => {
        const tenants = Array.isArray(payload?.availableTenants) ? payload.availableTenants : [];
        const preferredMatch = tenants.find(tenant =>
            typeof preferredTenantCode === 'string'
            && preferredTenantCode.length > 0
            && tenant.tenantCode.toLowerCase() === preferredTenantCode.toLowerCase());

        if (preferredMatch) {
            return preferredMatch.tenantCode;
        }

        if (payload?.activeTenantCode) {
            return payload.activeTenantCode;
        }

        return tenants[0]?.tenantCode || null;
    };

    const upsertSelector = () => {
        const topbarWrapper = document.querySelector('.swagger-ui .topbar-wrapper');
        if (!topbarWrapper) {
            return false;
        }

        let container = document.getElementById('swagger-tenant-selector-container');
        if (!container) {
            container = document.createElement('div');
            container.id = 'swagger-tenant-selector-container';
            container.style.display = 'flex';
            container.style.alignItems = 'center';
            container.style.gap = '8px';
            container.style.marginLeft = '16px';
            container.style.color = 'white';

            const label = document.createElement('label');
            label.htmlFor = 'swagger-tenant-selector';
            label.textContent = 'Tenant';
            label.style.fontSize = '14px';
            label.style.fontWeight = '600';

            const select = document.createElement('select');
            select.id = 'swagger-tenant-selector';
            select.style.padding = '4px 8px';
            select.style.borderRadius = '4px';
            select.style.border = '1px solid rgba(255,255,255,0.35)';
            select.style.background = 'white';
            select.style.color = '#1f2937';

            select.addEventListener('change', event => {
                const newTenantCode = event.target.value || null;
                if (newTenantCode === selectedTenantCode) {
                    return;
                }

                selectedTenantCode = newTenantCode;
                persistTenantCode(selectedTenantCode);
                authorizeWithTenant(selectedTenantCode);
            });

            container.appendChild(label);
            container.appendChild(select);
            topbarWrapper.appendChild(container);
        }

        const select = document.getElementById('swagger-tenant-selector');
        if (!select) {
            return false;
        }

        select.innerHTML = '';
        for (const tenant of availableTenants) {
            const option = document.createElement('option');
            option.value = tenant.tenantCode;
            option.textContent = `${tenant.tenantName} (${tenant.tenantCode})`;
            select.appendChild(option);
        }

        if (selectedTenantCode) {
            select.value = selectedTenantCode;
        }

        return true;
    };

    const ensureSelector = () => {
        let attemptsRemaining = 20;

        const tryRender = () => {
            if (upsertSelector() || attemptsRemaining <= 0) {
                return;
            }

            attemptsRemaining -= 1;
            window.setTimeout(tryRender, 300);
        };

        tryRender();
    };

    const initialize = async () => {
        const preferredTenantCode = getStoredTenantCode();

        const response = await window.fetch(runtimeConfigurationUrl, {
            headers: { 'Accept': 'application/json' }
        });
        const payload = await response.json();

        if (!response.ok || !payload?.activeTenantCode) {
            throw new Error(payload?.detail || 'Unable to load runtime tenant configuration for Swagger.');
        }

        availableTenants = Array.isArray(payload.availableTenants) ? payload.availableTenants : [];
        selectedTenantCode = resolveTenantCode(payload, preferredTenantCode);
        persistTenantCode(selectedTenantCode);
        ensureSelector();

        // Pre-authorize: Swagger UI's window.ui object may not be initialised at load time,
        // so poll briefly until it is available and then call preauthorizeApiKey.
        const waitForUiAndAuthorize = () => {
            if (window.ui?.preauthorizeApiKey) {
                authorizeWithTenant(selectedTenantCode);
                return;
            }

            window.setTimeout(waitForUiAndAuthorize, 200);
        };

        waitForUiAndAuthorize();
    };

    window.addEventListener('load', () => {
        initialize().catch(error => {
            console.error('Unable to initialize Swagger tenant selector.', error);
        });
    });
})();
