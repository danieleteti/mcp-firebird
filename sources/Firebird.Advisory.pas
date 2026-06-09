unit Firebird.Advisory;
interface
type
  TAdvisory = record
    Finding: string;
    SQLText: string;
    Verify: string;
    Severity: string;  // 'info' | 'warning' | 'critical'
    class function Make(const AFinding, ASQL, AVerify, ASeverity: string): TAdvisory; static;
  end;
implementation
class function TAdvisory.Make(const AFinding, ASQL, AVerify, ASeverity: string): TAdvisory;
begin
  Result.Finding := AFinding; Result.SQLText := ASQL; Result.Verify := AVerify; Result.Severity := ASeverity;
end;
end.
