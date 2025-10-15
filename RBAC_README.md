# Keila RBAC (Role-Based Access Control) System

This document describes the complete multi-tenant user management and role-based access control system implemented for Keila.

## 🎯 Overview

The RBAC system provides:
- **Multi-tenant isolation**: Users can only access their own tenant's resources
- **Role-based permissions**: Four distinct roles with different permission levels
- **Feature flags**: JSON permissions for frontend consumption
- **Super admin access**: Full system access across all tenants
- **Comprehensive testing**: Full test suite to verify functionality

## 🏗️ Architecture

### Core Components

1. **`Keila.RBAC`** - Main RBAC module with permission logic
2. **`Keila.RBACTestHelper`** - Test utilities and setup functions
3. **`Keila.RBACDemo`** - Demonstration and example usage
4. **Test Suites** - Comprehensive test coverage

### Database Schema

The system builds on Keila's existing auth system:
- **Users** (`users` table)
- **Accounts** (`accounts` table) - Represent tenants
- **Groups** (`groups` table) - Backing groups for accounts
- **Roles** (`roles` table) - Role definitions
- **Permissions** (`permissions` table) - Permission definitions
- **UserGroupRoles** (`user_group_roles` table) - User-role assignments

## 👥 Roles and Permissions

### Role Hierarchy

1. **Super Admin** (`super_admin`)
   - Full access to all tenants
   - Can manage users across all accounts
   - Can edit projects, view reports, manage billing
   - System-wide administrative privileges

2. **Admin** (`admin`)
   - Full access to their own tenant only
   - Cannot manage users
   - Can edit projects, view reports, manage billing
   - Tenant-level administrative privileges

3. **Editor** (`editor`)
   - Content editing access to their own tenant
   - Cannot manage users or billing
   - Can edit projects and view reports
   - Content creation and editing privileges

4. **Viewer** (`viewer`)
   - Read-only access to their own tenant
   - Cannot manage users, edit projects, or manage billing
   - Can only view reports
   - Read-only privileges

### Permission Matrix

| Permission | Super Admin | Admin | Editor | Viewer |
|------------|-------------|-------|--------|--------|
| `can_manage_users` | ✅ | ❌ | ❌ | ❌ |
| `can_edit_projects` | ✅ | ✅ | ✅ | ❌ |
| `can_view_reports` | ✅ | ✅ | ✅ | ✅ |
| `can_manage_billing` | ✅ | ✅ | ❌ | ❌ |

## 🏢 Multi-Tenant Setup

### Required Tenants

The system expects three tenants:

1. **Grim Digital**
   - `pigeon@grim-digital.com` → `super_admin`

2. **Dijagnoza**
   - `newsletter@dijagnoza.com` → `admin`
   - `editor@dijagnoza.com` → `editor`
   - `viewer@dijagnoza.com` → `viewer`

3. **Slikaj i Cirkaj**
   - `newsletter@slikajicirkaj.com` → `admin`
   - `editor@slikajicirkaj.com` → `editor`
   - `viewer@slikajicirkaj.com` → `viewer`

### Setup

The multi-tenant setup is automatically created by the seeds file:

```bash
mix run priv/repo/seeds.exs
```

## 🔧 API Reference

### Core Functions

#### `RBAC.get_role_permissions(role_name)`
Returns the permission map for a given role.

```elixir
RBAC.get_role_permissions(:super_admin)
# => %{
#   can_manage_users: true,
#   can_edit_projects: true,
#   can_view_reports: true,
#   can_manage_billing: true
# }
```

#### `RBAC.get_user_permissions(user_id, account_id)`
Returns the permission map for a user within a specific account.

```elixir
RBAC.get_user_permissions(user_id, account_id)
# => %{
#   can_manage_users: false,
#   can_edit_projects: true,
#   can_view_reports: true,
#   can_manage_billing: false
# }
```

#### `RBAC.user_has_permission?(user_id, account_id, permission)`
Checks if a user has a specific permission within an account.

```elixir
RBAC.user_has_permission?(user_id, account_id, :can_edit_projects)
# => true
```

#### `RBAC.get_user_role_in_account(user_id, account_id)`
Gets the role name for a user within a specific account.

```elixir
RBAC.get_user_role_in_account(user_id, account_id)
# => {:ok, :admin}
```

#### `RBAC.is_super_admin?(user_id)`
Checks if a user is a super admin.

```elixir
RBAC.is_super_admin?(user_id)
# => true
```

#### `RBAC.list_user_accessible_accounts(user_id)`
Lists all accounts that a user has access to.

```elixir
RBAC.list_user_accessible_accounts(user_id)
# => [%Account{...}, %Account{...}]
```

#### `RBAC.can_access_account?(user_id, account_id)`
Checks if a user can access a specific account.

```elixir
RBAC.can_access_account?(user_id, account_id)
# => true
```

#### `RBAC.list_account_users_with_roles(account_id)`
Gets all users in an account with their roles.

```elixir
RBAC.list_account_users_with_roles(account_id)
# => [{%User{...}, :admin}, {%User{...}, :editor}]
```

#### `RBAC.verify_multi_tenant_setup()`
Verifies that the multi-tenant setup is correct.

```elixir
RBAC.verify_multi_tenant_setup()
# => {:ok, %{tenants: [...], users: [...], role_permissions: [...]}}
```

## 🧪 Testing

### Running Tests

```bash
# Run all RBAC tests
mix test test/keila/rbac_simple_test.exs

# Run with specific tags
mix test --tag rbac_simple
```

### Test Coverage

The test suite covers:
- ✅ Role permission definitions
- ✅ User permission checking
- ✅ Multi-tenant access control
- ✅ Account user listing
- ✅ Super admin detection
- ✅ Cross-tenant isolation
- ✅ Permission inheritance

### Test Structure

1. **`RBACSimpleTest`** - Basic functionality tests
2. **`RBACTest`** - Integration tests with seeds data
3. **`RBACIntegrationTest`** - End-to-end multi-tenant tests
4. **`RBACTestHelper`** - Test utilities and setup

## 🎮 Demonstration

### Interactive Demo

```elixir
# Run the full demonstration
Keila.RBACDemo.run_demo()

# Create and test a scenario
Keila.RBACDemo.demonstrate_test_scenario()
```

### Manual Testing

```elixir
# Check if setup is correct
RBAC.verify_multi_tenant_setup()

# Get user permissions
user = Auth.find_user_by_email("pigeon@grim-digital.com")
account = Accounts.get_account(account_id)
permissions = RBAC.get_user_permissions(user.id, account.id)

# Check specific permission
RBAC.user_has_permission?(user.id, account.id, :can_manage_users)
```

## 🔒 Security Considerations

### Multi-Tenant Isolation

- Users can only access their own tenant's resources
- Super admins have explicit access to all tenants
- Account access is strictly controlled through the RBAC system

### Permission Checking

- All permission checks go through the RBAC module
- No direct database access for permission verification
- Consistent permission model across the application

### Role Management

- Roles are defined in code, not in the database
- Permission inheritance is handled programmatically
- Role assignments are validated through the auth system

## 🚀 Frontend Integration

### Feature Flags

The permission maps can be consumed by the frontend to control UI visibility:

```javascript
// Example frontend usage
const permissions = await getUserPermissions(userId, accountId);

if (permissions.can_manage_users) {
  showUserManagementUI();
}

if (permissions.can_edit_projects) {
  showProjectEditor();
}

if (permissions.can_view_reports) {
  showReportsTab();
}
```

### API Endpoints

The RBAC system can be integrated with API endpoints:

```elixir
def show_users(conn, %{"account_id" => account_id}) do
  user_id = get_current_user_id(conn)
  
  if RBAC.user_has_permission?(user_id, account_id, :can_manage_users) do
    users = RBAC.list_account_users_with_roles(account_id)
    json(conn, %{users: users})
  else
    conn
    |> put_status(:forbidden)
    |> json(%{error: "Insufficient permissions"})
  end
end
```

## 📝 Usage Examples

### Creating a New User with Role

```elixir
# Create user
{:ok, user} = Auth.create_user(%{email: "new@example.com", password: "password"})
{:ok, _} = Auth.activate_user(user.id)

# Create account
{:ok, account} = Accounts.create_account()

# Assign user to account
:ok = Accounts.set_user_account(user.id, account.id)

# Create and assign role
{:ok, role} = Auth.create_role(%{name: "editor"})
:ok = Auth.assign_role_to_user(user.id, %{account_id: account.id, role_id: role.id})

# Verify permissions
permissions = RBAC.get_user_permissions(user.id, account.id)
# => %{can_manage_users: false, can_edit_projects: true, ...}
```

### Checking Access Before Operations

```elixir
def create_project(conn, %{"account_id" => account_id} = params) do
  user_id = get_current_user_id(conn)
  
  # Check if user can edit projects in this account
  if RBAC.user_has_permission?(user_id, account_id, :can_edit_projects) do
    # Create project
    {:ok, project} = Projects.create_project(params)
    json(conn, %{project: project})
  else
    conn
    |> put_status(:forbidden)
    |> json(%{error: "Cannot edit projects"})
  end
end
```

## 🔧 Maintenance

### Adding New Permissions

1. Update the permission map in `RBAC.get_role_permissions/1`
2. Add tests for the new permission
3. Update frontend feature flags
4. Update API endpoints to check the new permission

### Adding New Roles

1. Add the role to the `role_name` type in `RBAC`
2. Implement `get_role_permissions/1` for the new role
3. Add tests for the new role
4. Update documentation

### Database Migrations

The RBAC system uses existing Keila tables. No additional migrations are required.

## 📚 Related Documentation

- [Keila Auth System](lib/keila/auth/auth.ex)
- [Keila Accounts](lib/keila/accounts/accounts.ex)
- [Test Factories](test/support/factory.ex)
- [Database Seeds](priv/repo/seeds.exs)

## 🤝 Contributing

When contributing to the RBAC system:

1. Add tests for new functionality
2. Update documentation
3. Ensure multi-tenant isolation is maintained
4. Verify permission inheritance works correctly
5. Test with the demonstration script

## 📄 License

This RBAC system is part of the Keila project and follows the same license terms.
