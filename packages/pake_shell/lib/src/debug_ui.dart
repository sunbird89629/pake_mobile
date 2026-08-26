import 'package:flutter/foundation.dart';

/// 设置页里的调试项（URL、User agent、抓包开关、日志、请求列表、重置）只在
/// debug 构建里出现。正式包里它们对普通用户没有意义，而 URL 和 UA 改错了还会
/// 把这个壳变成一个打不开的空白页——那时唯一的退路是重置，而重置本身也在这
/// 一组里。
///
/// 错误页也读它：正式包里那句「open settings to change it」指向的输入框已经
/// 不在了，不能再那么说。
///
/// 已经装在真机上的正式包要现场排查时，用
/// `--dart-define=PAKE_DEBUG_UI=true` 重新出一个包把它们打开。
const kShowDebugSettings = kDebugMode || bool.fromEnvironment('PAKE_DEBUG_UI');
