(function () {
    const tenantStorageKey = 'order-processing:selected-tenant';
    const runtimeConfigurationUrl = '/api/v1/info/runtime-configuration';
    // window.OrderProcessingActiveTenant is read by the Swagger UI requestInterceptor
    // (configured in Program.cs UseSwaggerUI) to inject X-Tenant-Code on every API call.
    // When login is added, the auth module sets the same global — no JS changes needed here.
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

    const setActiveTenant = tenantCode => {
        window.OrderProcessingActiveTenant = tenantCode || null;
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
                setActiveTenant(selectedTenantCode);
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

        // Pre-set the global immediately from localStorage so the Swagger UI requestInterceptor
        // already has the correct tenant for any request fired before our init completes.
        // The server call below confirms the stored tenant is still valid and may override it.
        if (preferredTenantCode) {
            setActiveTenant(preferredTenantCode);
        }

        // Include the stored tenant in the initialization fetch so the server returns data
        // in the context of the preferred tenant rather than the configured default.
        // Note: requestInterceptor is Swagger UI-only — it does not apply to raw window.fetch.
        const initHeaders = preferredTenantCode
            ? { 'Accept': 'application/json', 'X-Tenant-Code': preferredTenantCode }
            : { 'Accept': 'application/json' };

        const response = await window.fetch(runtimeConfigurationUrl, { headers: initHeaders });
        const payload = await response.json();

        if (!response.ok || !payload?.activeTenantCode) {
            throw new Error(payload?.detail || 'Unable to load runtime tenant configuration for Swagger.');
        }

        availableTenants = Array.isArray(payload.availableTenants) ? payload.availableTenants : [];
        selectedTenantCode = resolveTenantCode(payload, preferredTenantCode);
        persistTenantCode(selectedTenantCode);
        setActiveTenant(selectedTenantCode); // Re-confirm with server-validated value
        ensureSelector();
    };

    window.addEventListener('load', () => {
        initialize().catch(error => {
            console.error('Unable to initialize Swagger tenant selector.', error);
        });
    });
})();
