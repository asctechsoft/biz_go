import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/setup_account_screen.dart';
import '../features/customers/customer_detail_screen.dart';
import '../features/customers/customer_edit_screen.dart';
import '../features/customers/customers_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/dashboard/notifications_screen.dart';
import '../features/dashboard/quick_filter_screen.dart';
import '../features/delivery/delivery_hub_screen.dart';
import '../features/more/audit_log_screen.dart';
import '../features/more/carriers_screen.dart';
import '../features/more/customer_debts_screen.dart';
import '../features/more/invoice_settings_screen.dart';
import '../features/more/more_screen.dart';
import '../features/more/reports_screen.dart';
import '../features/more/user_management_screen.dart';
import '../features/orders/create/create_order_screen.dart';
import '../features/orders/order_detail_screen.dart';
import '../features/orders/orders_screen.dart';
import '../features/products/product_detail_screen.dart';
import '../features/products/products_screen.dart';
import '../features/warehouse/warehouse_screen.dart';
import '../models/order_filter.dart';
import '../providers/auth_provider.dart';
import '../features/splash/splash_screen.dart';
import '../shell/main_shell.dart';
import 'permissions.dart';

GoRouter buildRouter(AuthProvider auth) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: auth,
    redirect: (context, state) {
      final atSplash = state.matchedLocation == '/splash';
      // Đang khởi động → giữ splash.
      if (auth.status == AuthStatus.unknown) {
        return atSplash ? null : '/splash';
      }
      // Đang đăng nhập → đứng yên (login screen tự hiện spinner).
      if (auth.status == AuthStatus.loading) return null;

      final loggedIn = auth.status == AuthStatus.authenticated;
      final loggingIn = state.matchedLocation == '/login';
      final role = auth.user?.role;

      if (!loggedIn) return (loggingIn) ? null : '/login';

      // Lần đầu đăng nhập (tài khoản bootstrap) → khoá ở màn thiết lập tài
      // khoản, không cho vào route nào khác cho tới khi đổi SĐT + mật khẩu.
      final atSetup = state.matchedLocation == '/setup-account';
      if (auth.mustSetupAccount) return atSetup ? null : '/setup-account';
      if (atSetup) return role == null ? '/dashboard' : Perm.home(role);

      // Đã đăng nhập mà đang ở splash/login → về màn chính theo vai trò.
      if (atSplash || loggingIn) {
        return role == null ? '/dashboard' : Perm.home(role);
      }
      // Chặn route ngoài quyền → đưa về màn chính của vai trò.
      if (role != null && !Perm.canRoute(role, state.matchedLocation)) {
        return Perm.home(role);
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (c, s) => const SplashScreen()),
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(
        path: '/setup-account',
        builder: (c, s) => const SetupAccountScreen(),
      ),
      // Bottom-nav shell
      ShellRoute(
        builder: (c, s, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (c, s) => const DashboardScreen(),
          ),
          GoRoute(path: '/orders', builder: (c, s) => const OrdersScreen()),
          GoRoute(
            path: '/delivery',
            builder: (c, s) => const DeliveryHubScreen(),
          ),
          GoRoute(path: '/more', builder: (c, s) => const MoreScreen()),
        ],
      ),
      // Full-screen pushed routes
      GoRoute(path: '/customers', builder: (c, s) => const CustomersScreen()),
      GoRoute(
        path: '/notifications',
        builder: (c, s) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/filter',
        // `extra` = bộ lọc đang áp dụng, để mở lên thấy đúng thứ đang lọc.
        builder: (c, s) => QuickFilterScreen(
          initial: s.extra is OrderFilter
              ? s.extra as OrderFilter
              : OrderFilter.empty,
        ),
      ),
      GoRoute(
        path: '/orders/create',
        builder: (c, s) => const CreateOrderScreen(),
      ),
      GoRoute(
        path: '/orders/:id',
        builder: (c, s) => OrderDetailScreen(orderId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/customers/new',
        builder: (c, s) => const CustomerEditScreen(),
      ),
      GoRoute(
        path: '/customers/:id',
        builder: (c, s) =>
            CustomerDetailScreen(customerId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/products', builder: (c, s) => const ProductsScreen()),
      GoRoute(
        path: '/products/:id',
        builder: (c, s) =>
            ProductDetailScreen(productId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/warehouse', builder: (c, s) => const WarehouseScreen()),
      GoRoute(path: '/reports', builder: (c, s) => const ReportsScreen()),
      GoRoute(path: '/users', builder: (c, s) => const UserManagementScreen()),
      GoRoute(path: '/audit', builder: (c, s) => const AuditLogScreen()),
      GoRoute(path: '/carriers', builder: (c, s) => const CarriersScreen()),
      GoRoute(path: '/debts', builder: (c, s) => const CustomerDebtsScreen()),
      GoRoute(
        path: '/invoice-settings',
        builder: (c, s) => const InvoiceSettingsScreen(),
      ),
    ],
  );
}
