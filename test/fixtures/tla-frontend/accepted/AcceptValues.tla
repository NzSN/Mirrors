---- MODULE AcceptValues ----

Tuple == <<1, 2, 3>>
Record == [first |-> 1, second |-> "text"]
Set == {1, 2, 3}
Empty == {}
Nested == <<[a |-> {1, 2}], <<"x">>, TRUE, FALSE>>
Escapes == "quote\" backslash\\ tab\t newline\n"

====
