import superstruct;

// - operations between superstructs and non-superstructs -----
// slicing/indexing
unittest {
  SuperStruct!(int[]) i = [0,1,2];
  assert(i[] == [0,1,2]);
  assert(i[1] == 1);
  assert(i[1..2] == [1]);
  //assert(i[1..$] == [1]);
}

// binary arithmetic
unittest {
  SuperStruct!int i = 5;
  assert(-i    == -5);
  assert(i + 5 == 10);
  assert(i - 5 == 0);
  assert(i * 5 == 25);
  assert(i / 5 == 1);

  assert((i += 5) == 10 && i == SuperStruct!int(10));
  assert((i -= 5) == 5  && i == SuperStruct!int(5 ));
  assert((i *= 5) == 25 && i == SuperStruct!int(25));
  assert((i /= 5) == 5  && i == SuperStruct!int(5 ));

  assert(i + i == 10);
}

// concatenation
unittest {
  SuperStruct!(int[]) i = [1,2,3];
  i ~= 4;
  assert(i == SuperStruct!(int[])([1,2,3,4]));
}

// equality
unittest {
  struct One { bool opEquals(int i) { return i == 1; } }
  struct Two { bool opEquals(int i) { return i == 2; } }

  SuperStruct!(One, Two) one = One();
  SuperStruct!(One, Two) two = Two();

  assert(one == 1);
  assert(one != 2);
  assert(two != 1);
  assert(two == 2);
}

// - operations between two superstructs ----------------------
// binary arithmetic
unittest {
  alias SS = SuperStruct!int;
  SS i = 4;
  SS j = 2;

  assert(i + j == 6); // 4 + 2
  assert(i - j == 2); // 4 - 2
  assert(i * j == 8); // 4 * 2
  assert(i / j == 2); // 4 / 2

  assert((i += j) == 6 && i == SS(6)); // 4 + 2 == 6
  assert((i -= j) == 4 && i == SS(4)); // 6 - 2 == 4
  assert((i *= j) == 8 && i == SS(8)); // 4 * 2 == 8
  assert((i /= j) == 4 && i == SS(4)); // 8 / 2 == 4
}

// concatenation
unittest {
  alias SS = SuperStruct!(int[]);

  SS a = [1,2,3];
  SS b = [4,5,6];

  assert((a ~= b) == [1,2,3,4,5,6]);
  assert(a == [1,2,3,4,5,6]);
}

// equality
unittest {
  alias SS = SuperStruct!(int, float);

  SS a = 1;
  SS b = 2;

  assert(a == a);
  assert(a != b);
}

// equality
unittest {
  struct A { int i; }
  struct B { int i; }
  struct C {
    int i;
    bool opEquals(T)(T other) { return other.i == i; }
  }

  SuperStruct!(A, B, C) a0 = A(0);
  SuperStruct!(A, B, C) a1 = A(1);
  SuperStruct!(A, B, C) b0 = B(0);
  SuperStruct!(A, B, C) c0 = C(0);

  assert(a0 == a0);
  assert(a1 == a1);
  assert(a0 != a1);
  assert(a0 != b0);
  assert(a1 != b0);
  assert(a0 == c0); // C is comparable to A
  assert(c0 == a0); // C is comparable to A
}
