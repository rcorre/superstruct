import superstruct;

// public/public:
unittest {
  struct A { int i; }
  struct B { int i; }
  SuperStruct!(A, B) ab;
  static assert(__traits(compiles, { auto i = ab.i; } ));
}

// public/private
unittest {
  struct A { int i; }
  struct B { private int i; }
  SuperStruct!(A, B) ab;
  static assert(!__traits(compiles, { auto i = ab.i; } ));
}

// package/private
unittest {
  struct A { int i; }
  struct B { package int i; }
  SuperStruct!(A, B) ab;
  static assert(!__traits(compiles, { auto i = ab.i; } ));
}

// private/private
unittest {
  struct A { private int i; }
  struct B { private int i; }
  SuperStruct!(A, B) ab;
  static assert(!__traits(compiles, { auto i = ab.i; } ));
}
