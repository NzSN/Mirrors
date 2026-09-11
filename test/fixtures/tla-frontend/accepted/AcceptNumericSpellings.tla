---- MODULE AcceptNumericSpellings ----

EXTENDS Integers

Decimal == 255
Octal == \o377
Hex == \hFF
Binary == \b11111111

Sum == Decimal + Octal + Hex + Binary

====
