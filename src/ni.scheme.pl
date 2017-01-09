u("ni.scheme:ni.scheme")->create('ni.behavior.code',
  name        => 'An unstructured behavior described by a block of code',
  synopsis    => 'u("ni.behavior.code:<code>")->modify(u"ni.scheme:<scheme>")',
  description => q{
    Evaluates the specified code within the Perl package corresponding to a
    scheme. No higher-level structure is imposed on the code, so instances of
    this class are functionally opaque.

    In general you should try to use more structured behaviors, but this one is
    provided to make it possible to promote URIs directly into code; this
    simplifies ni's bootstrapping logic.})

  ->uses(u"ni.behavior.code:$ni::behavior_code_meta_boot");

u("ni.scheme:ni.scheme")->create('ni.behavior.alias',
  name        => 'Provides a named constructor function for a class',
  synopsis    => 'u("ni.scheme:<name>")->uses(u"ni.behavior.alias:<fname>")',
  description => q{
    Creates a function in the ni:: namespace that generates instances of this
    class. Calling the function is equivalent to calling the class's create()
    method on the given arguments.})

  ->uses(u"ni.behavior.code:" . q{
    # TODO
  });

u("ni.scheme:ni.scheme")->create('ni.fn',
  name        => 'A function, optionally with annotations',
  synopsis    => q{ u("ni.fn:<code>")
                  | fn(@annotations, '<code>')
                  | fn(@annotations, '<args>' => '<code>') },
  description => q{
    Compiles the specified code into a callable object. Functions can install
    themselves into Perl's symbol table, a property used by behaviors when
    modifying classes.})

  ->uses(u"ni.behavior.code:" . q{
    use overload qw/&{} as_fn/;
    # TODO
  });

u("ni.scheme:ni.scheme")->create('ni.scheme',
  name        => 'URI scheme describing URI schemes',
  synopsis    => ' u"ni.scheme:http"->u("google.com")
                 | u"ni.scheme:ni.rmi.pid"->behaviors ',
  description => q{
    # Introduction
    This is the fixed-point definition at the core of ni's meta-object
    protocol: it is the class of which other classes and itself are instances.
    It is only definable because ni's bootstrap code sets up enough cached
    objects to convincingly pretend as though the ni.scheme metaclass is
    available for instantiation (i.e. this circular definition isn't redundant
    the first time the code is run).

    ## History
    ni originally represented itself as a naïve self-replicating hashtable of
    string attributes, some of which contained code and would be evaluated.
    This is also the model used by self-modifying Perl objects
    (https://github.com/spencertipping/perl-objects), though the internal
    formats differ between the two projects.

    One of the major deficiencies of that approach is that Perl code isn't
    really data; when ni serialized itself, it included comments and other
    non-operative elements because parsing Perl isn't generally possible.
    Correspondingly, it was unable to calculate dependencies and produce a
    smaller version of itself customized for specific use cases. This version
    of ni uses a reflective object system as its primary replication primitive,
    solving those problems by migrating its self-awareness to a structural
    level.

    ## Architectural features
    Metadata erasure makes it possible to extend ni's introspection to include
    documentation, unit tests, runtime factor diagnostics, and other elements
    that would otherwise be too large to include in a self-replicating image.
    This means ni can not only execute a process, but also take some steps to
    find out why a process can't be executed (or to build an alternative
    strategy to do something). Under this model, unit tests are useful not only
    to diagnose repeatable failures, but also for ni to evaluate possibilities
    at runtime.

    ni stores its original image, which ordinarily would make reflective
    metaprogramming doubly expensive: every long string like this documentation
    would be stored not only in the initial image but also as a
    runtime-allocated string. However, ni's boot image is invariant and
    attributes are represented verbatim (that is, their bytes are within
    fixed-point regions of the Perl evaluator); this means we can rereference
    almost every string as a byte range in the original image with almost no
    overhead.

    # URI addressing
    Every object in ni's system can be referred to using a URI-like string. ni
    provides the "u" function to convert a URI to an object reference, which
    will do one of two things:

    1. If an object with that URI already exists, "u" returns the object.
    2. Otherwise, "u" constructs a new object from the URI and returns that.

    This represents a factoring over object state: invariants are contained in
    the URI/identity, and each object's mutable state is entirely contained
    within a single name.

    # Defining classes
    Each scheme represents a class of object, and instances of ni.scheme are
    themselves classes. Unlike in most object-oriented languages, classes have
    no direct support for methods; these are generated by adding behaviors
    (instances of ni.behavior), which execute code within a scheme's Perl
    package.})

  ->uses(u"ni.behavior.code:$ni::scheme_meta_boot");
