#!/usr/bin/env perl
$ni::license = <<'_';
ni: https://github.com/spencertipping/ni
Copyright (c) 2016-2017 Spencer Tipping

MIT license

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
_
eval($ni::context{'ni.module:/boot'} = <<'_');
sub ni::context {
  my @r = @ni::context{@_};
  return @r unless grep !defined, @r;
  die 'ni::context: failed to resolve '
    . join(', ', grep !defined($ni::context{$_}), @_);
}

package ni::serializable;
sub dependencies {
  my @immediates = @_;
  my %ds = ($immediates[0] => 1);
  my @ds;
  while (@immediates = grep !exists $ds{$_},
                       map $_->immediate_dependencies, @immediates) {
    @ds{@immediates} = @immediates;
    push @ds, @immediates;
  }
  @ds;
}
sub serialize {
  my $self = shift;
  $_->serialize_self(@_) for reverse $self->dependencies;
  $self->serialize_self(@_);
  shift;
}
sub serialize_self {
  my ($self, $into) = @_;
  $into << ni::quote(ref($self) . '::')->new(%$self{sort keys %$self});
}

package ni::named;
sub name {shift->{name}}

package ni::transient_identity;
push our @ISA, 'ni::named';
use Scalar::Util qw/weaken/;
sub DESTROY {delete $ni::context{shift->name}}
sub add_to_context {my $self = shift; weaken($ni::context{$self->name} = $self); $self}

package ni::persistent_identity;
push our @ISA, 'ni::named';
sub add_to_context {my $self = shift; $ni::context{$self->name} = $self}

package ni::boot_module;
push our @ISA, qw/ni::serializable ni::persistent_identity/;
sub immediate_dependencies {}
sub serialize_self {
  my ($self, $into) = @_;
  $into << join "\n", qq{eval(\$ni::context{'$$self{name}'} = <<'_');},
                      $$self{code},
                      '_',
                      qq{die "\$@ evaluating $$self{name}" if \$@;};
}
sub new {
  my $class = shift;
  my $self = bless {name => $_[0], code => $_[1]}, $class;
  chomp $$self{code};
  $self->add_to_context;
  $self;
}
ni::boot_module->new('ni.module:/boot', ni::context 'ni.module:/boot');

package ni::module;
push our @ISA, qw/ni::serializable ni::persistent_identity/;
sub new {
  my $class = shift;
  my $self = bless {@_}, $class;
  $self->add_to_context;
  $self->eval;
  $self;
}
sub eval {my $self = shift; eval $$self{code}; die "$@ evaluating $$self{name}" if $@}
sub immediate_dependencies {ni::context @{shift->{dependencies}}}
_
die "$@ evaluating ni.module:/boot" if $@;
ni::module->new(name         => 'ni.module:/lib/quote',
                dependencies => ['ni.module:/boot'],
                code         => <<'_');
sub ni::quote($)       {bless {expr => shift}, 'ni::quotation'}
sub ni::quote_hash($)  {ni::quote '{' . join(',', map ni::quote_value($_), %{+shift}) . '}'}
sub ni::quote_array($) {ni::quote '[' . join(',', map ni::quote_value($_), @{+shift}) . ']'}
sub ni::quote_context_lookup($) {"ni::context(" . ni::quote_scalar(shift) . ")"}
sub ni::quote_scalar($) {
  my $v = shift;
  return 'undef' unless defined $v;
  return $v if Scalar::Util::looks_like_number $v;
  $v =~ s/([\\'])/\\$1/g;
  "q'$v'";
}
sub ni::quote_value($) {
  my $v = shift;
  return ni::quote_hash($v)  if 'HASH'  eq ref $v;
  return ni::quote_array($v) if 'ARRAY' eq ref $v;
  return ni::quote_context_lookup($v->name) if ref $v;
  ni::quote_scalar($v);
}

package ni::quotation;
use Scalar::Util;
use overload qw/"" __str/;
push @ni::quotation::method_call::ISA, 'ni::quotation';
our $AUTOLOAD;
sub AUTOLOAD {
  my $self = shift;
  (my $method = $AUTOLOAD) =~ s/^.*:://;
  bless {receiver => $self,
         method   => $method,
         args     => [map ni::quote_value($_), @_]},
        'ni::quotation::method_call';
}
sub __str {shift->{expr}}
sub ni::quotation::method_call::__str {
  my $self = shift;
  join '', $$self{receiver}, '->', $$self{method},
           '(', join(',', @{$$self{args}}), ')';
}
_
ni::module->new(name         => 'ni.module:/lib/printer',
                dependencies => ['ni.module:/lib/quote'],
                code         => <<'_');
package ni::printer;
use overload qw/<< print/;
sub new {
  my $class = shift;
  bless {fh => shift}, $class;
}
sub print {shift->{fh}->print(@_, ';')}
$ni::context{'ni.module:/lib/printer'}->serialize(ni::printer->new(\*STDOUT));
_
