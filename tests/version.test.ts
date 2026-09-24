import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// B9：网页包版本与 iOS 工程版本必须一致，防止发布时漏改。
describe('版本一致性', () => {
  it('package.json、iOS MARKETING_VERSION 与 build 号一致', () => {
    const pkg = JSON.parse(readFileSync(resolve(process.cwd(), 'package.json'), 'utf-8'));
    const pbx = readFileSync(resolve(process.cwd(), 'ios/App/App.xcodeproj/project.pbxproj'), 'utf-8');
    const marketing = [...pbx.matchAll(/MARKETING_VERSION = ([0-9.]+);/g)].map(m => m[1]);
    const current = [...pbx.matchAll(/CURRENT_PROJECT_VERSION = (\d+);/g)].map(m => m[1]);
    expect([...new Set(marketing)]).toEqual([pkg.version]);
    expect([...new Set(current)]).toEqual(['8']);
    expect(pkg.version).toBe('1.0.2');
  });
});
