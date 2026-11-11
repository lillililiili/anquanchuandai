import test from 'node:test';
import assert from 'node:assert/strict';
import { csvContent } from '../src/lib/files.js';

const oneCell = value => csvContent(['字段'], [[value]]).slice('\ufeff"字段"\r\n'.length);

test('CSV exports neutralize each direct formula introducer as text', () => {
  for (const value of ['=1+1', '+1', '-1', '@SUM(A1)']) {
    assert.equal(oneCell(value), '"\'' + value + '"');
  }
});

test('CSV exports neutralize formula introducers after leading whitespace', () => {
  for (const value of [' =1+1', '\t=1+1', '\r+1', '\n-1', ' \t\r@SUM(A1)', '\ufeff=1+1', '\u00a0@SUM(A1)']) {
    assert.equal(oneCell(value), '"\'' + value + '"', JSON.stringify(value));
  }
});

test('CSV exports neutralize formula introducers after C0, DEL and C1 controls', () => {
  for (const value of ['\u0000=1+1', '\u0000\u007f+1', '\u001f-1', '\u0085@SUM(A1)', '\u009f=1+1', ' \u0000\t\u007f\ufeff@SUM(A1)']) {
    assert.equal(oneCell(value), '"\'' + value + '"', JSON.stringify(value));
  }
});

test('CSV protection applies to headers and every data cell before quote escaping', () => {
  assert.equal(
    csvContent(['\t=标题', '普通列'], [['\ufeff+1', '\r@SUM("A1")'], ['第二行', '=1+1']]),
    '\ufeff"\'\t=标题","普通列"\r\n"\'\ufeff+1","\'\r@SUM(""A1"")"\r\n"第二行","\'=1+1"',
  );
});

test('ordinary Chinese, embedded operators, commas, quotes and line breaks retain their content', () => {
  assert.equal(
    csvContent(['名称', '说明'], [['普通中文', 'a,"b"\r\n下一行'], ['人员 =1+1', '\t普通值'], ['\u0000普通值', 'A+1']]),
    '\ufeff"名称","说明"\r\n"普通中文","a,""b""\r\n下一行"\r\n"人员 =1+1","\t普通值"\r\n"\u0000普通值","A+1"',
  );
});

test('CSV exports keep null handling, scalar conversion and input arrays unchanged', () => {
  const headers = Object.freeze(['空值', '未定义', '零', '布尔', '负数']);
  const row = Object.freeze([null, undefined, 0, false, -12]);
  const rows = Object.freeze([row]);
  assert.equal(csvContent(headers, rows), '\ufeff"空值","未定义","零","布尔","负数"\r\n"","","0","false","\'-12"');
  assert.deepEqual(row, [null, undefined, 0, false, -12]);
});
