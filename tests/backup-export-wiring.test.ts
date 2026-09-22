import { readFileSync } from 'node:fs';
import { expect, it } from 'vitest';

// Windows 可执行的 SwiftUI 接线检查，不冒充 iOS 交互测试。
// 原生 ErrorPathTests 另行核对同数量恢复后的 JSON 内容。
it('备份按钮在点击时序列化当前账本，不使用页面级导出缓存', () => {
  const source = readFileSync('ios/App/App/StockLedger/SettingsView.swift', 'utf8');
  const view = source.split('struct BackupRestoreView: View {')[1].split('struct LedgerInfoView: View {')[0];
  expect(view).toContain('Button(action: exportBackup)');
  expect(view).not.toMatch(/@State[^\n]*\bexportText\b/);
  const action = view.split('private func exportBackup() {')[1];
  expect(action).toContain('shareBox = ShareBox(value: try LedgerStore.exportText(state.ledger))');
  expect(action).toContain('shareBox = nil');
  expect(action).toContain('Diagnostics.record("EXPORT", error: error)');
});
