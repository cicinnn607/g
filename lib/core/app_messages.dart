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

String friendlyAnalysisReportError(Object error) {
  final message = _errorText(error);
  final lower = message.toLowerCase();
  final detail = _shortErrorDetail(message);

  String withDetail(String reason) {
    if (detail.isEmpty) return '$reason 当前显示基础规则报告。';
    return '$reason 当前显示基础规则报告。技术信息：$detail';
  }

  if (lower.contains('missing_llm_config') ||
      lower.contains('missing env: analysis_llm_api_key') ||
      lower.contains('missing env: zhipu_api_key')) {
    return withDetail('AI 配置缺失，还没有配置智谱或分析模型 API Key。');
  }
  if (lower.contains('missing env: supabase_service_role_key')) {
    return withDetail('分析服务缺少 Supabase 服务端配置。');
  }
  if (lower.contains('llm_timeout') ||
      lower.contains('timeoutexception') ||
      lower.contains('timeout') ||
      lower.contains('请求超时') ||
      lower.contains('等待超时')) {
    return withDetail('AI 等待超时，已经按 60 秒等待策略处理。');
  }
  if (lower.contains('invalid_analysis_report')) {
    return withDetail('AI 输出未通过安全校验。');
  }
  if (lower.contains('insufficient_data')) {
    return withDetail('可用于 AI 报告的数据不足。');
  }
  if (lower.contains('llm_http_400')) {
    return withDetail('AI 请求参数异常，请看技术信息里的模型服务返回内容。');
  }
  if (lower.contains('llm_http_401') || lower.contains('llm_http_403')) {
    return withDetail('AI 服务鉴权失败，请检查服务端 API Key。');
  }
  if (lower.contains('llm_http_429')) {
    return withDetail('AI 服务额度或频率受限。');
  }
  if (RegExp(r'llm_http_5\d\d').hasMatch(lower)) {
    return withDetail('AI 服务暂时异常。');
  }
  if (lower.contains('llm_http_')) {
    return withDetail('AI 服务返回异常。');
  }
  if (lower.contains('function not found') ||
      lower.contains('analysis-report') && lower.contains('not found') ||
      lower.contains('edge function') && lower.contains('not found') ||
      lower.contains('404') && lower.contains('analysis-report')) {
    return withDetail('分析服务未部署，或线上 Edge Function 还不是最新版本。');
  }
  if (lower.contains('unauthorized') || lower.contains('401')) {
    return withDetail('登录状态失效，分析服务没有拿到有效授权。');
  }
  if (lower.contains('failed host lookup') ||
      lower.contains('socketexception') ||
      lower.contains('network') ||
      lower.contains('connection')) {
    return withDetail('网络连接异常，暂时连不上分析服务。');
  }
  if (lower.contains('500') ||
      lower.contains('internal server') ||
      lower.contains('functionexception') ||
      lower.contains('functionshttperror')) {
    return withDetail('分析服务运行异常。');
  }
  return withDetail('AI 报告请求失败。');
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
  if (lower.contains('该模型当前访问量过大') ||
      lower.contains('ai 服务当前比较忙') ||
      lower.contains('too many requests') ||
      lower.contains('rate limit') ||
      lower.contains('service unavailable') ||
      lower.contains('functionexception') && lower.contains('500') ||
      lower.contains('functionexception') && lower.contains('503') ||
      lower.contains('internal server error') && lower.contains('ai')) {
    return '$action失败：AI 服务当前比较忙，请稍后重试。';
  }
  return '$action失败：$message';
}

String _shortErrorDetail(String message) {
  final cleaned = message
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('Exception: ', '')
      .replaceAll('StateError: ', '')
      .trim();
  if (cleaned.isEmpty) return '';
  if (cleaned.length <= 120) return cleaned;
  return '${cleaned.substring(0, 120)}...';
}

String _errorText(Object error) {
  if (error is PostgrestException) {
    return [error.message, error.code, '${error.details}', '${error.hint}']
        .map((part) => '$part')
        .where((part) => part.trim().isNotEmpty && part != 'null')
        .join(' ');
  }
  return '$error';
}
