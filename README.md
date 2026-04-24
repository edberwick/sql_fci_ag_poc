# SQL FCI AG POC

This Terraform configuration creates three Azure Windows VMs in separate VNETs across three Azure regions (UK South, UK West, North Europe) to demonstrate replication using Availability Groups. You will need to install SQL Server on the VMs and configure the AG manually.

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Terraform installed (v1.14.9 or later)
- Sufficient Azure quota for VMs

## Deployment

1. Initialize Terraform:
   ```
   terraform init
   ```

2. Validate the configuration:
   ```
   terraform validate
   ```

3. Plan the deployment:
   ```
   terraform plan
   ```

4. Apply the configuration:
   ```
   terraform apply -auto-approve
   ```

## Post-Deployment: Installing SQL Server and Setting Up Availability Groups

After the VMs are created:

1. **Access the VMs**:
   - Use Azure Bastion from the Azure portal to RDP into each VM securely (no public IPs needed on VMs).
   - Go to each VM in the portal, click "Connect" > "Bastion", and use the admin credentials (adminuser / Password123!).

2. **Install SQL Server** on each VM:
   - RDP into each VM using Bastion.
   - Download and install SQL Server 2022 (or your preferred version) from Microsoft's website or use the SQL Server Installation Center.
   - Configure SQL Server with mixed authentication mode and set a strong SA password.

3. **Domain Setup (Recommended for AG)**:
   - For proper AG functionality, join the VMs to a domain or set up a workgroup with proper networking.
   - Ensure the VMs can communicate over the required ports (1433 for SQL, 5022 for AG, etc.).

4. **Configure Availability Groups**:
   - Create databases on the primary VM.
   - Set up the AG using SQL Server Management Studio or T-SQL scripts.
   - Add the secondary VMs as replicas.

For detailed steps, refer to: [Always On Availability Groups for SQL Server on Azure VMs](https://docs.microsoft.com/en-us/azure/azure-sql/virtual-machines/windows/availability-group-overview)

## Networking Notes

- **Egress to Internet**: NSGs are configured to allow outbound traffic to the internet from the VM subnets.
- **Secure Access**: Azure Bastion is deployed in each region for secure RDP access to VMs without exposing them publicly.

## Cleanup

To destroy the resources:
```
terraform destroy -auto-approve
```

## Notes

- VMs use Standard_D2s_v5 size with Windows Server 2022.
- Password is set to "Password123!" - change in production.
- For cross-region AG, ensure VNET peering or ExpressRoute for connectivity.
- This is for POC purposes; adjust VM sizes and configurations as needed for production.

## Azure Portal Links

After deployment, view the resources in the Azure portal:
- [UK South Resource Group](https://portal.azure.com/#@yourtenant.onmicrosoft.com/resource/subscriptions/your-subscription-id/resourceGroups/rg-sql-poc-uksouth)
- [UK West Resource Group](https://portal.azure.com/#@yourtenant.onmicrosoft.com/resource/subscriptions/your-subscription-id/resourceGroups/rg-sql-poc-ukwest)
- [North Europe Resource Group](https://portal.azure.com/#@yourtenant.onmicrosoft.com/resource/subscriptions/your-subscription-id/resourceGroups/rg-sql-poc-northeurope)

Replace `your-subscription-id` and `yourtenant.onmicrosoft.com` with your actual values.