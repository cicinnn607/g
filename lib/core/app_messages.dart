import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

bool isMissingSchemaError(Object error, {String? table}) {
  final message = _errorText(error).toLowerCase();
  final tableName = table?.toLowerCase();
  final tableMatches =
      tableName == null ||
      message.contains(tableName) ||
      message.contains(tableName.replaceAll('_', ''));

  final isPostgrestSchemaError =
      error is PostgrestException &&
      (error.code == 'PGRST205' || error.code == '404');
  final hasSchemaMessage =
      message.contains('pgrst205') ||
      message.contains('could not find the table') ||
      message.contains('schema cache') ||
      (message.contains('not found') && tableMatches);

  return tableMatches && (isPostgrestSchemaError || hasSchemaMessage);
}

String friendlyMealRecognitionError(Object error) {
  final message = _errorText(error);
  final lower = message.toLowerCase();
  if (lower.contains('bucket not found') ||
      lower.contains('bucket_not_found') ||
      lower.contains('the resource was not found') ||
      lower.contains('meal-images') && lower.contains('not found')) {
    return '食物图片存储桶未配置，请同步 Supabase migration。';
  }
  if (lower.contains('function not found') ||
      lower.contains('404') && lower.contains('recognize-meal') ||
      lower.contains('edge function') && lower.contains('not found')) {
    return '识别服务未部署。';
  }
  if (lower.contains('missing env: baidu_api_key') ||
      lower.contains('missing env: baidu_secret_key')) {
    return '识别服务缺少百度 API 配置。';
  }
  if (lower.contains('missing env: supabase_service_role_key')) {
    return '识别服务缺少 Supabase 服务端配置。';
  }
  return message;
}

String friendlyActionError(Object error, {String action = '操作'}) {
  final message = _errorText(error);
  final lower = message.toLowerCase();

  if (isMissingSchemaError(error, table: 'reminder_settings')) {
    if (kReleaseMode) {
      return '$action失败：提醒功能暂时不可用，请稍后重试。';
    }
    return '$action失败：远端数据库缺少 reminder_settings 表或 schema cache 未刷新，请同步 Supabase migration。';
  }
  if (isMissingSchemaError(error)) {
    if (kReleaseMode) {
      return '$action失败：数据同步异常，请稍后重试。';
    }
    return '$action失败：远端数据库结构未同步或 schema cache 未刷新：$message';
  }
  if (lower.contains('permission denied') || message.contains('42501')) {
    return '$action失败：数据库权限不足，请先在 Supabase 执行最新 migration 后再试。';
  }
  if (message.contains('还没有配置 Supabase anon key')) {
    return '$action失败：还没有配置 Supabase anon key。';
  }
  if (message.contains('请先登录')) {
    return '$action失败：请先登录。';
  }
  return '$action失败：$message';
}

String _errorText(Object error) {
  if (error is PostgrestException) {
    return [
      error.message,
      error.code,
      '${error.details}',
      '${error.hint}',
    ]
        .map((part) => '$part')
        .where((part) => part.trim().isNotEmpty && part != 'null')
        .join(' ');
  }
  return '$error';
}
