- [ ] **Resource Management** (20 min)
  - [ ] Create resource group: `rg-orderprocessing-dev`
  - [ ] Understand Azure resource hierarchy and naming conventions
  - [ ] Set up cost management and budgets



-----------------------------------
how to setup currency as rupees in azure

To set up **Indian Rupees (INR ₹)** as your **currency in Azure**, you need to ensure that your **billing account and subscription** are configured for India. Azure determines the currency based on your **billing country/region**, and **you can't change the currency after the subscription is created**.

---

## ✅ Ways to Use INR (₹) in Azure

### 📌 1. **Create a New Subscription with India as Billing Country**

* Currency is locked **based on the country** selected at the time of subscription creation.
* If you choose **India** as your **billing country**, your Azure bills and estimates will be shown in **INR**.

> ⚠️ You **cannot change** the billing currency of an existing subscription (e.g., from USD to INR).

---

### 🔧 Steps to Set Currency in New Subscription (INR):

1. Go to: [https://azure.microsoft.com/en-in/free/](https://azure.microsoft.com/en-in/free/)
   (note the `en-in` region — it sets India as your billing country)

2. Click **Start free** (for trial) or sign in and choose **Pay-As-You-Go**.

3. During **account setup**:

   * Choose **India** as your billing country.
   * Enter an Indian **PAN card number**, **phone**, and **payment method** (credit/debit card in INR).
   * Your account will now use **INR** as the default billing currency.

---

### 📈 2. **View Pricing in INR in Azure Pricing Calculator**

* Go to: [Azure Pricing Calculator](https://azure.microsoft.com/en-in/pricing/calculator/)
* The `en-in` version of the site automatically shows pricing in **INR ₹**.
* If it still shows USD, scroll to the **bottom right** of the page:

  * Click on **Currency** dropdown
  * Choose **INR (₹)** manually

> 🔁 This does **not affect your actual billing currency**, just the **pricing display** in the calculator.

---

### 🔎 3. **Check Your Billing Currency**

You can confirm the currency for your current subscription:

1. Go to **Azure Portal**: [https://portal.azure.com](https://portal.azure.com)
2. Search for **“Cost Management + Billing”**
3. Click on **Billing profiles**
4. Click on your **billing account**
5. You’ll see your **billing currency** (e.g., USD or INR)

---

## 🧾 Need INR Billing for an Existing Account?

Unfortunately:

* ❌ Azure does **not allow changing currency** for existing subscriptions.
* ✅ You can **create a new subscription** under the same account, with India as billing region, to use INR.

---

## ✅ Summary

| Task                               | Steps                                                                                                            |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| **Set INR as billing currency**    | Create a new subscription with **India** as billing country                                                      |
| **View pricing in INR**            | Use the [Azure Pricing Calculator (India)](https://azure.microsoft.com/en-in/pricing/calculator/) and select INR |
| **Check current billing currency** | Go to **Cost Management + Billing > Billing Profiles** in the portal                                             |

---

Would you like help creating a **new INR-based subscription**, or do you want to explore costs in INR for specific services?







-----------------------------------
# Resource Management in Azure - Overview

In Azure, resource management involves organizing, controlling, and overseeing resources like virtual machines, databases, storage, and networking components. Azure offers tools for grouping, managing, and ensuring efficient use of resources while maintaining cost and governance.

## 1. Create Resource Group: `rg-orderprocessing-dev` (5-7 minutes)

A **Resource Group (RG)** is a logical container that holds related Azure resources (VMs, storage accounts, databases, etc.) for easier management, access control, and monitoring.

### Why Create a Resource Group?

- Organize resources logically by project, environment, or lifecycle.
- Apply policies and manage resources together (scaling, permissions).
- Streamline cost and billing reports.

### Syntax for Creating a Resource Group

**Using Azure CLI:**
```sh
az group create --name rg-orderprocessing-dev --location eastus
```

**Using Azure Portal:**
1. Go to the Azure Portal.
2. In the left sidebar, select **Resource groups**.
3. Click **+ Create**.
4. Choose the Subscription and Region (e.g., East US).
5. Enter the Resource Group Name (`rg-orderprocessing-dev`).
6. Click **Review + Create**, then **Create**.

---

## 2. Understand Azure Resource Hierarchy and Naming Conventions (5-7 minutes)

Azure uses a hierarchical model for organizing resources:

### Azure Resource Hierarchy

1. **Management Groups**
   - Highest level; organize subscriptions at the enterprise level.
   - Used for managing policies across multiple subscriptions.

2. **Subscriptions**
   - Logical container for Azure resources.
   - Tied to billing account; managed with RBAC and policies.

3. **Resource Groups**
   - Containers for related resources.
   - Resources share the same lifecycle and can be managed as a unit.

4. **Resources**
   - Actual Azure services/products (VMs, storage, networks, etc.).
   - Reside in resource groups and subscriptions.

### Naming Conventions

- **Resource Group:** `rg-[projectname]-[environment]`  
  _Example:_ `rg-orderprocessing-dev`
- **VMs:** `vm-[appname]-[environment]-[region]`  
  _Example:_ `vm-orderprocessor-dev-eastus`
- **Storage Accounts:** Globally unique  
  _Example:_ `stororderprocessordev`
- **Networking:** Logical, standardized names  
  _Example:_ `vnet-orderprocessor-dev`

**Key Points:**
- Keep names short but descriptive.
- Use hyphens (`-`) to separate words.
- Include environment (e.g., dev, prod).
- Ensure global uniqueness for resources like storage accounts and databases.

---

## 3. Set Up Cost Management and Budgets (5-7 minutes)

Cost management is crucial for controlling and tracking Azure spending. Azure provides Cost Management and Billing tools to monitor, allocate, and manage costs.

### Steps

#### Create a Budget

A budget helps control and track spending by setting thresholds for different resource categories.

**How to Set Up a Budget:**
1. Go to the Azure Portal.
2. Search for **Cost Management + Billing**.
3. Select **Budgets** from the sidebar.
4. Click **+ Add** to create a new budget.
5. Choose the Subscription and specify the Resource Group or Service.
6. Set the budget amount and time period (monthly, quarterly, annually).
7. Set up alerts for budget thresholds.
8. Click **Create**.

#### Review Cost Analysis

- View cost analysis dashboards to track spending vs. budget.
- Filter by resource group, service, region, etc.

#### Set Up Alerts

- Alerts notify you when spending exceeds thresholds.
- Azure Cost Management has integrated alerting capabilities.

---

## In Summary

- **Resource Group:** Logical containers to group resources (`rg-orderprocessing-dev`).
- **Azure Hierarchy:** Organizes resources at different levels (Management Groups, Subscriptions, Resource Groups, Resources).
- **Naming Conventions:** Structured names for consistency and manageability.
- **Cost Management and Budgets:** Track and manage costs, stay within budget.

✅ Tips to View and Apply Naming Conventions:

There’s no strict enforcement by default, but you can:

Use Azure Tags to add structured metadata to each resource (like Environment=Dev, Project=OrderProcessing).

Set up Azure Policy later to enforce naming if needed.

--------

# How to Enforce Naming Conventions in Azure

Consistent naming across Azure resources improves clarity, scalability, automation, cost tracking, and governance.

---

## Why Naming Conventions Matter

- **Clarity:** Instantly identify a resource’s purpose, environment, and ownership.
- **Compliance:** Azure enforces naming rules (length, allowed characters, uniqueness) per resource type.
- **Immutability:** Many resources cannot be renamed after creation—plan ahead!
- **Governance:** Supports automation, cost management, and policy enforcement.

---

## Recommended Naming Components (CAF-Aligned)

Adopt these components for all resources, tailored to your organization:

- **Organization:** e.g., `con`, `fab`
- **Business Unit:** e.g., `payroll`, `exp`
- **Resource Type:** e.g., `rg`, `vm`, `vnet`
- **Workload/Project:** e.g., `orderprocessing`, `emissions`
- **Environment:** e.g., `dev`, `prod`, `qa`
- **Region:** e.g., `neu` (North Europe), `eus` (East US)
- **Instance Number:** e.g., `01`, `02` (for differentiation)

**Best Practices:**
- Use hyphens (`-`) for readability.
- Use abbreviations for brevity.
- Stick to lowercase to avoid confusion.
- Avoid spaces and special characters (except hyphens where allowed).

---

## Practical Naming Format Examples

| Resource Type      | Format Example                      | Sample Name                |
|--------------------|-------------------------------------|----------------------------|
| Resource Group     | `<org>-<product>-rg-<env>-<region>` | `con-payroll-rg-dev-neu`   |
| Virtual Machine    | `<org>-<project>-vm-<env>-<instance>` | `fab-exp-vm-prd-01`        |
| Storage Account    | `<project><env>sa` (no separators)  | `emissionsdevsa`           |

---

## Enforcing Naming Conventions

### 1. **Azure Policy**
- Create or assign policies to audit or deny resource creation if names don’t match your convention.
- Example: [Azure Policy documentation](https://learn.microsoft.com/en-us/azure/governance/policy/)

### 2. **PSRule for Azure**
- DevOps-friendly tool for enforcing naming and tagging rules.
- Supports customizable rules and CAF baseline rules.
- Example: [PSRule for Azure](https://github.com/Azure/PSRule.Rules.Azure)

---

## Summary & Next Steps

1. **Define** your naming convention: components, order, delimiters, abbreviations, case style.
2. **Document & Communicate** standards to your team.
3. **Enforce** using Azure Policy or PSRule to audit/block non-compliant names.
4. **Use Tags** for mutable metadata (e.g., cost center, owner)—don’t overload resource names.

---

**References:**
- [Microsoft Learn: Naming Rules](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/naming-and-tagging)
- [Azure Documentation](https://learn.microsoft.com/en-us/azure/)
- [PSRule for Azure](https://github.com/Azure/PSRule.Rules.Azure)
---------------------------------------------

# Subscription Management in Azure (30 min)

Subscription management helps you structure your Azure environment, control costs, and plan resource usage efficiently.

---

## ✅ Overview

- **Subscription:** Container for all Azure resources; defines billing and access boundaries.
- **Quota:** Predefined resource limit (e.g., number of VMs).
- **Limit:** Hard boundary—cannot exceed unless increased by Microsoft.

---

## 🔹 1. Understand Subscription Limits and Quotas (10 min)

Every Azure subscription has service-specific quotas and limits.

### 📌 Key Terms

- **Subscription:** Tied to billing; all resources are deployed under it.
- **Quota:** Maximum allowed for a resource (soft limit).
- **Limit:** Absolute maximum (hard limit).

### 💡 Common Quotas

| Resource Type                | Quota/Limit                |
|------------------------------|----------------------------|
| Virtual Machines (vCPUs)     | 10–20 vCPUs per region     |
| Public IP Addresses          | 10 per region              |
| Storage Accounts             | 250 per region             |
| Azure SQL DBs per server     | 5000 databases             |

### 🔍 How to View & Request Increases

- **Azure Portal:**  
  Go to **Subscriptions > Usage + quotas**
- **Azure CLI:**  
  ```sh
  az vm list-usage --location eastus
  ```

[Learn more: Azure subscription and service limits, quotas, and constraints](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/azure-subscription-service-limits)

---

## 🔹 2. Set Up Cost Alerts and Spending Limits (10 min)

Azure provides tools to help you avoid overspending.

### ✅ Cost Alerts

- Set via **Cost Management + Billing**.
- Go to **Budgets > + Add**.
- Set a threshold (e.g., $100).
- Add email alerts for 80%, 90%, and 100% spend.

### ✅ Spending Limits

- **Spending limit:** Hard cap; Azure pauses services when reached.
- **Available only for:** Free/trial or MSDN subscriptions.
- **Not available for:** Pay-As-You-Go or Enterprise Agreements.

> For paid subscriptions, use budgets and alerts—no enforced spend limit.

---

## 🔹 3. Explore Azure Pricing Calculator (10 min)

Estimate monthly costs before deploying resources.

- [Azure Pricing Calculator](https://azure.com/pricing/calculator)

### 🧭 How to Use

1. Go to the website and select products (e.g., VMs, SQL DB).
2. Choose region and configuration (VM size, OS, disk type).
3. View estimated monthly cost.
4. Add more services to simulate full environments.
5. Download/export quote (Excel/PDF).

### 💡 Tips

- Include storage and bandwidth costs.
- Use “Dev/Test pricing” for non-production workloads.
- Consider Reserved Instances for long-term savings (up to 72%).

---

## 🧩 Summary Table

| Task                       | Purpose                              | Tools                        |
|----------------------------|--------------------------------------|------------------------------|
| Understand Limits & Quotas | Avoid resource provisioning errors   | Azure Portal, Azure CLI      |
| Set Cost Alerts / Budgets  | Get notified before overspending     | Cost Management + Billing    |
| Spending Limits            | Hard caps on certain subscriptions   | Azure Portal (trial/MSDN)    |
| Pricing Calculator         | Forecast Azure spend before deploying| Azure Pricing Calculator     |

---

## ✅ Suggested Practice Flow (30-min Exercise)

| Time      | Task                                                        |
|-----------|-------------------------------------------------------------|
| 0–10 min  | Review current subscription limits via Azure Portal          |
| 10–20 min | Set up a budget alert for $100 and test notification        |
| 20–30 min | Build sample architecture (1 VM + SQL DB) in Pricing Calculator and export cost estimate |

---

By following these steps, you’ll efficiently manage your Azure subscription, control costs, and plan resources
-------------------------------------------------

## ✅ 1. Set a Budget Alert Specific to a Resource Group

**Goal:**  
Get email alerts when spending in a particular resource group (e.g., `rg-orderprocessing-dev`) exceeds a threshold.

### 🔹 Steps in Azure Portal

1. Go to [Azure Portal](https://portal.azure.com)
2. In the top search bar, type **Cost Management + Billing** and click it.
3. In the left menu, select **Cost Management > Budgets**.
4. Click **+ Add** to create a new budget.

#### 📋 Step-by-Step Form

**a) Scope**
- Choose your Subscription.
- Click **Select scope**.
- Go to **Resource groups** tab and select `rg-orderprocessing-dev`.
- ✅ The budget now applies only to this resource group.

**b) Name and Settings**
- **Budget name:** `orderprocessing-dev-budget`
- **Reset period:** Monthly
- **Start/end dates:** Accept defaults
- **Budget amount:** e.g., $100
- Click **Next**.

**c) Set Alerts**
- Add alert conditions:
  - **80% threshold:** Add your email.
  - **90% threshold:** (Optional)
  - **100% threshold:** Required.
- Email alerts will be sent when spending reaches these levels.
- Click **Review + Create**, then **Create**.

✔️ **Done:** You’ll now get email notifications when costs hit the limits for that resource group.

---

## ✅ 2. Create a Sample Estimate in Azure Pricing Calculator

**Goal:**  
Estimate cost for a small Order Processing Dev Environment (VM + SQL + Storage).

### 🔗 [Azure Pricing Calculator](https://azure.com/pricing/calculator)

### 🔹 Sample Setup

Estimate for:
- 1 Virtual Machine (B2s)
- 1 Azure SQL Database (Basic tier)
- 1 Storage Account (General Purpose v2)

### 🧭 Steps

1. Click **+ Add Products** at the top.
2. Add:
   - **Virtual Machines**
   - **SQL Database**
   - **Storage Accounts**

#### 1️⃣ Configure Virtual Machine
- **Region:** East US
- **OS:** Windows or Linux
- **Tier:** Dev/Test
- **Instance:** B2s (2 vCPU, 4 GB RAM)
- **Hours:** 730 (full month)
- **Disk:** 64 GB Standard HDD (default)
- **Estimated:** ~$30–$50/month

#### 2️⃣ Configure SQL Database
- **Region:** East US
- **Deployment:** Single database
- **Tier:** Basic
- **Storage:** 2 GB
- **Estimated:** ~$5/month

#### 3️⃣ Configure Storage
- **Region:** East US
- **Account type:** General Purpose v2
- **Redundancy:** LRS (Locally redundant)
- **Capacity:** 100 GB
- **Transactions:** 100,000 (estimate)
- **Estimated:** ~$3–$5/month

### 📤 Export Estimate
- Scroll to the bottom.
- Click **Export** or **Share** to get:
  - Link
  - Excel file
  - PDF file

✔️ **You now have a cost estimate for your dev

-------------------------------------------------------


Absolutely! Let’s walk through both parts of your request step-by-step:

---

## 1.  **Set Up a Budget Alert Specific to a Resource Group**

### Goal:

Receive email alerts when spending in a specific resource group—say, `rg-orderprocessing-dev`—reaches certain thresholds.

### Steps on Azure Portal:

1. Go to [Azure Portal](https://portal.azure.com).
2. Search for **“Cost Management + Billing”** and open it.
3. In the left menu, navigate to **Cost Management → Budgets**.
4. Click **+ Add** to create a new budget.
5. Configure the form:

   * **Scope**: Select the subscription, then choose **Resource Groups**, and pick `rg-orderprocessing-dev`.
   * **Name**: e.g., `orderprocessing-dev-budget`.
   * **Reset Period**: Monthly.
   * **Budget Amount**: e.g., \$100.
6. Click **Next** to configure alerts:

   * Add thresholds (e.g., 80%, 90%, 100%) and enter email addresses for notifications.
7. Review and click **Create**.

You’ll now receive alerts when spend for that resource group approaches or exceeds your set thresholds.

---

## 2.  **Build a Sample Estimate in Azure Pricing Calculator**

### Goal:

Create a cost estimate for a development setup (VM + SQL DB + Storage), and then generate a shareable link or document.

### How to Use the Calculator:

The **Azure Pricing Calculator** is a free, web-based tool that helps you forecast monthly costs by configuring Azure services.([Microsoft Learn][1])

#### Key Features:

* Real-time pricing via Azure Retail Prices API.([Microsoft Learn][1], [Petri IT Knowledgebase][2])
* Customizable options: region, tier, usage hours, and more.
* Supports cost-saving options like reserved instances and Azure Hybrid Benefit.([Nexa Lab][3], [Synextra][4])
* Export options: Excel, PDF, or shareable link.([Microsoft Learn][1], [Petri IT Knowledgebase][2])

#### Sample Estimate Setup (East US Region):

1. Go to the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) and add:

   * **Virtual Machines**
   * **SQL Database**
   * **Storage Account**

2. Configure each:

   * **Virtual Machine**:

     * Region: East US
     * VM Type: B2s (2 vCPUs, 4 GB RAM)
     * Hours/month: 730
     * OS: Linux (or Windows, if needed)
     * Tier: Dev/Test (if applicable)
   * **SQL Database**:

     * Single database
     * Basic tier
   * **Storage Account**:

     * General Purpose v2, LRS (Locally Redundant Storage)
     * 100 GB capacity

3. The calculator dynamically updates estimated costs for each product as configured.([Microsoft Learn][1], [Petri IT Knowledgebase][2])

4. To save or share:

   * Click **Export** for PDF/Excel, or **Share** to get a direct link.([Microsoft Learn][1], [Petri IT Knowledgebase][2])

---

### Tip:

Want a quicker way to estimate? Here’s a **template link** that you can paste into the Calculator's URL bar to pre-load an estimate similar to the one described above:

```
https://azure.microsoft.com/pricing/calculator/?service=virtual-machines,sql-database,storage-account
```

Once in the calculator, just customize region, VM size, and configurations to match your needs.

---

## Summary Table

| Task                          | Description                                                               |
| ----------------------------- | ------------------------------------------------------------------------- |
| Budget Alert (Resource Group) | Alerts you when spending in a specified resource group crosses thresholds |
| Pricing Calculator Estimate   | Forecast costs for VM + SQL DB + Storage and export/share results         |

---

Would you like me to walk you through customizing that template link further or help generate the shared estimate link directly online?

[1]: https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/pricing-calculator?utm_source=chatgpt.com "Estimate costs with the Azure pricing calculator - Microsoft Cost Management | Microsoft Learn"
[2]: https://petri.com/using-azure-pricing-calculator/?utm_source=chatgpt.com "How to Use the Azure Pricing Calculator - Petri IT Knowledgebase"
[3]: https://blog.octobits.io/digital-transformation/microsoft-azure-pricing-calculator/?utm_source=chatgpt.com "Microsoft Azure Pricing Calculator: How To Calculate & Tips - Octobits Learning Center"
[4]: https://www.synextra.co.uk/knowledge-base/the-azure-pricing-calculator/?utm_source=chatgpt.com "The Complete Guide To The Azure Pricing Calculator"





-------------------------------------------------------
By following these steps and principles, your Azure resources will be organized effectively, easy to manage, and cost-efficient.