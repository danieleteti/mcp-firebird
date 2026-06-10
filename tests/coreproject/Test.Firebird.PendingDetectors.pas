unit Test.Firebird.PendingDetectors;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TPendingDetectorTests = class
  public
    [Test][Ignore('M2: non-sargable predicate detection not implemented yet')]
    procedure Detects_NonSargable_LeadingWildcard;
    [Test][Ignore('M2: implicit conversion detection not implemented yet')]
    procedure Detects_ImplicitConversion;
    [Test][Ignore('M2: oversized index key check not implemented yet')]
    procedure Flags_Oversized_IndexKey;
  end;
implementation
procedure TPendingDetectorTests.Detects_NonSargable_LeadingWildcard; begin end;
procedure TPendingDetectorTests.Detects_ImplicitConversion; begin end;
procedure TPendingDetectorTests.Flags_Oversized_IndexKey; begin end;
end.
