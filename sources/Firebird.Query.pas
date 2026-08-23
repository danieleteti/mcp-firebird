// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit Firebird.Query;

{ Runs a caller's SELECT and returns the rows.

  Everything else in this server executes a query to say something *about* it — a plan, a cost,
  a goal — and throws the rows away. That is the right default for a tool that advises, and the
  wrong one at the end of every advice loop: "the index is used now" is a claim about a plan,
  and the question that follows it is always what the query actually returns.

  Two things bound it. IsReadOnlySelect refuses anything that is not a plain SELECT before a
  statement reaches the engine (the read-only TPB refuses it again, and means it); and a row cap
  that is applied by *not fetching* past it, so a SELECT * over twenty million rows costs the
  rowset it was capped at, not the table. }

interface

uses Firebird.Connection;

type
  TQueryResult = record
    Columns: TArray<string>;
    { Rows already rendered as text: a row of a result set is not a Delphi type, and the one
      consumer is a Markdown table read by a language model. }
    Rows: TArray<TArray<string>>;
    Executed: Boolean;
    { Why the statement was not run, when Executed is False. Never empty in that case. }
    SkipReason: string;
    { True when the engine still had rows to give when this stopped fetching. }
    Truncated: Boolean;
    { True when what stopped it was the size of the answer rather than the row cap. A row cap
      bounds rows, not width: a hundred rows of a forty-column table is a hundred rows and half
      a megabyte of Markdown. }
    TruncatedBySize: Boolean;
    MaxRows: Integer;
    ElapsedMs: Int64;
    function ToMarkdown: string;
  end;

const
  { Enough rows to see the shape of an answer, few enough that the answer stays readable to
    whoever asked. A caller who needs more says so, up to ROW_CEILING. }
  DEFAULT_MAX_ROWS = 100;
  ROW_CEILING = 1000;
  { A single VARCHAR(32000) would otherwise decide how wide the table is. }
  CELL_LIMIT = 200;
  { And the row cap alone would not bound the answer either: rows are capped, width is not.
    Whatever the shape of the table, the result stops being added to at roughly this many
    characters — a few pages of table, which is as much as an answer can be and stay one. }
  CHARACTER_BUDGET = 20000;

{ Executes ASQL and returns up to AMaxRows rows. AMaxRows <= 0 means DEFAULT_MAX_ROWS; anything
  above ROW_CEILING is clamped to it. Never raises for a refused statement — the reason comes
  back in the result; a genuine engine error (bad table name, syntax) still raises, so the tool
  layer reports it as one. }
function RunSelect(AConn: TFirebirdConnection; const ASQL: string; AMaxRows: Integer): TQueryResult;

implementation

uses System.SysUtils, System.Generics.Collections, System.Diagnostics, Data.DB, FireDAC.Comp.Client;

{ A pipe is a column separator in a Markdown table and content everywhere else. Column names
  come from the caller's SELECT and can be quoted identifiers, so a header cell needs the same
  escaping a data cell does. }
function EscapePipes(const AText: string): string;
begin
  Result := AText.Replace('|', '\|');
end;

function CellText(AField: TField): string;
begin
  if AField.IsNull then
    Exit('NULL');
  { A binary blob rendered as text is line noise at best and megabytes of it at worst. Text
    blobs are readable and get the same truncation as any other long value. }
  if AField.DataType = ftBlob then
    Exit('(blob)');
  Result := AField.AsString;
  { A newline inside a cell ends the row as far as a Markdown table is concerned, and a pipe
    starts a new column. Both are content here, not structure. }
  Result := EscapePipes(Result.Replace(#13#10, ' ').Replace(#13, ' ').Replace(#10, ' '));
  if Result.Length > CELL_LIMIT then
    Result := Result.Substring(0, CELL_LIMIT) + '…';
end;

function RunSelect(AConn: TFirebirdConnection; const ASQL: string; AMaxRows: Integer): TQueryResult;
var
  Q: TFDQuery;
  SW: TStopwatch;
  lRows: TList<TArray<string>>;
  lIdx: Integer;
  lBudget: Integer;
begin
  Result := Default(TQueryResult);
  Result.MaxRows := AMaxRows;
  if Result.MaxRows <= 0 then
    Result.MaxRows := DEFAULT_MAX_ROWS;
  if Result.MaxRows > ROW_CEILING then
    Result.MaxRows := ROW_CEILING;

  if not IsReadOnlySelect(ASQL) then
  begin
    Result.SkipReason := 'this is not a plain SELECT. This server reads; it does not write, and ' +
      'the transactions it opens carry the read-only TPB, so the engine would refuse the ' +
      'statement even if this check let it through';
    Exit;
  end;
  if HasParameters(ASQL) then
  begin
    Result.SkipReason := 'the statement carries placeholders nobody bound. FireDAC would send ' +
      'them as NULL, and rows selected by `= NULL` are not the rows this query returns — ' +
      'substitute the literal values you mean and run it again';
    Exit;
  end;

  lRows := TList<TArray<string>>.Create;
  try
    SW := TStopwatch.StartNew;
    Q := AConn.OpenQuery(ASQL);
    try
      SetLength(Result.Columns, Q.FieldCount);
      for lIdx := 0 to Q.FieldCount - 1 do
        Result.Columns[lIdx] := EscapePipes(Q.Fields[lIdx].FieldName);
      lBudget := CHARACTER_BUDGET;
      while (not Q.Eof) and (lRows.Count < Result.MaxRows) and (lBudget > 0) do
      begin
        { A fresh array per row, declared here on purpose. One variable reused across the loop
          works only because SetLength copies an array the list already holds a reference to,
          and that is not a rule anybody should have to remember while editing this. }
        var lRow: TArray<string>;
        SetLength(lRow, Q.FieldCount);
        for lIdx := 0 to Q.FieldCount - 1 do
        begin
          lRow[lIdx] := CellText(Q.Fields[lIdx]);
          Dec(lBudget, Length(lRow[lIdx]) + 3);  // the cell, plus its ' | ' separator
        end;
        lRows.Add(lRow);
        Q.Next;
      end;
      { The row that spent the last of the budget is kept: it was read, and a result that ends
        one row short of what it fetched is harder to reason about than one that says it
        stopped. }
      Result.TruncatedBySize := (lBudget <= 0) and (lRows.Count < Result.MaxRows);
      { Eof is only meaningful after the loop has stopped fetching: at the cap the engine has
        been asked for nothing beyond it, so "not Eof" is exactly "there was more". }
      Result.Truncated := not Q.Eof;
    finally
      Q.Free;
    end;
    Result.ElapsedMs := SW.ElapsedMilliseconds;
    Result.Rows := lRows.ToArray;
    Result.Executed := True;
  finally
    lRows.Free;
  end;
end;

function TQueryResult.ToMarkdown: string;
var
  SB: TStringBuilder;
  lRow: TArray<string>;
  lIdx: Integer;
begin
  if not Executed then
    Exit('**Not executed:** ' + SkipReason + '.');
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('| ' + string.Join(' | ', Columns) + ' |');
    for lIdx := 0 to High(Columns) do
      SB.Append('|---');
    SB.AppendLine('|');
    for lRow in Rows do
      SB.AppendLine('| ' + string.Join(' | ', lRow) + ' |');
    SB.AppendLine;
    if Truncated and TruncatedBySize then
      SB.AppendLine(Format('**%d row(s) in %d ms — stopped at %d characters, before the cap of ' +
        '%d rows.** This table is too wide to send a hundred rows of: select the columns you ' +
        'need instead of `*`, and the row cap will be what bounds the answer.',
        [Length(Rows), ElapsedMs, CHARACTER_BUDGET, MaxRows]))
    else if Truncated then
      SB.AppendLine(Format('**%d row(s) in %d ms — stopped at the cap of %d.** The query has ' +
        'more to give: narrow it with a WHERE, aggregate it, or raise max_rows (up to %d).',
        [Length(Rows), ElapsedMs, MaxRows, ROW_CEILING]))
    else
      SB.AppendLine(Format('**%d row(s) in %d ms.**', [Length(Rows), ElapsedMs]));
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
