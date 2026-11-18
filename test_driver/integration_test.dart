// flutter drive 驱动脚本（integration_test 官方约定）：
//   flutter drive --driver=test_driver/integration_test.dart \
//                --target=test/integration/app_flow_test.dart -d chrome
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
