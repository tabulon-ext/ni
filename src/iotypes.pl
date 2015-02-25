BEGIN {

use List::Util qw/min max/;
use POSIX qw/dup2/;

sub to_fh {
  return undef unless defined $_[0];
  return $_[0]->() if ref $_[0] eq 'CODE';
  return $_[0]     if ref $_[0] eq 'GLOB';
  open my $fh, $_[0] or die "failed to open $_[0]: $!";
  $fh;
}

# Partial implementations
defio 'sink_as',
sub { +{description => $_[0], f => $_[1]} },
{
  explain         => sub { "[sink as: " . ${$_[0]}{description} . "]" },
  supports_reads  => sub { 0 },
  supports_writes => sub { 1 },
  sink_gen        => sub { ${$_[0]}{f}->(@_[1..$#_]) },
};

defio 'source_as',
sub { +{description => $_[0], f => $_[1]} },
{
  explain    => sub { "[source as: " . ${$_[0]}{description} . "]" },
  source_gen => sub { ${$_[0]}{f}->(@_[1..$#_]) },
};

sub sink_as(&)   { ni_sink_as("[anonymous sink]", @_) }
sub source_as(&) { ni_source_as("[anonymous source]", @_) }

# Bidirectional filehandle IO with lazy creation
defio 'file',
sub {
  die "ni_file() requires three constructor arguments (got @_)" unless @_ == 3;
  +{description => $_[0], reader => $_[1], writer => $_[2]}
},
{
  explain => sub { ${$_[0]}{description} },

  reader_fh => sub {
    my ($self) = @_;
    die "io not configured for reading" unless $self->supports_reads;
    $$self{reader} = to_fh $$self{reader};
  },

  writer_fh => sub {
    my ($self) = @_;
    die "io not configured for writing" unless $self->supports_writes;
    $$self{writer} = to_fh $$self{writer};
  },

  supports_reads  => sub { defined ${$_[0]}{reader} },
  supports_writes => sub { defined ${$_[0]}{writer} },
  has_reader_fh   => sub { ${$_[0]}->supports_reads },
  has_writer_fh   => sub { ${$_[0]}->supports_writes },

  source_gen => sub {
    my ($self, $destination) = @_;
    gen 'file_source:V', {fh   => $self->reader_fh,
                          body => $destination->sink_gen('L')},
      q{ while (<%:fh>) {
           chomp;
           @_ = split /\t/;
           %@body
         } };
  },

  sink_gen => sub {
    my ($self, $type) = @_;
    with_input_type $type,
      gen 'file_sink:L', {fh => $self->writer_fh},
        q{ print %:fh join("\t", @_) . "\n"; };
  },

  close => sub { close $_[0]->writer_fh; $_[0] },
};

# An array of stuff in memory
defio 'memory',
sub { [@_] },
{
  explain => sub {
    "[memory io of " . scalar(@{$_[0]}) . " element(s): "
                     . "[" . join(', ', @{$_[0]}[0 .. min(3, $#{$_[0]})],
                                        @{$_[0]} > 4 ? ("...") : ()) . "]]";
  },

  supports_writes => sub { 1 },
  process_local   => sub { 1 },

  source_gen => sub {
    my ($self, $destination) = @_;
    gen 'memory_source:VV', {xs   => $self,
                             body => $destination->sink_gen('O')},
      q{ for (@{%:xs}) {
           @_ = ($_);
           %@body
         } };
  },

  sink_gen => sub {
    my ($self) = @_;
    gen 'memory_sink:FV', {xs => $self}, q{ push @{%:xs}, @_; };
  },
};

# A ring buffer of a specified size
defio 'ring',
sub { die "ring must contain at least one element" unless $_[0] > 0;
      my $n = 0;
      +{xs       => [map undef, 1..$_[0]],
        overflow => $_[1],
        n        => \$n} },
{
  explain => sub {
    my ($self) = @_;
    "[ring io of " . min(${$$self{n}}, scalar @{$$self{xs}})
                   . " element(s)"
                   . ($$self{overflow} ? ", > $$self{overflow}]"
                                       : "]");
  },

  supports_writes => sub { 1 },
  process_local   => sub { 1 },

  source_gen => sub {
    my ($self, $destination) = @_;
    my $i     = ${$$self{n}};
    my $size  = @{$$self{xs}};
    my $start = max 0, $i - $size;

    # Emit two loops, one before and one after the break. This way we won't end
    # up doing a modulus per loop iteration.
    gen 'ring_source:VV', {xs    => $$self{xs},
                           n     => $size,
                           end   => $i % $size,
                           i     => $start % $size,
                           body  => $destination->sink_gen('O')},
      q{ while (%:i < %@n) {
           @_ = (${%:xs}[%:i++]);
           %@body
         }
         %:i = 0;
         while (%:i < %@end) {
           @_ = (${%:xs}[%:i++]);
           %@body
         } };
  },

  sink_gen => sub {
    my ($self, $type) = @_;
    if (defined $$self{overflow}) {
      gen "ring_sink:${type}V", {xs   => $$self{xs},
                                 size => scalar(@{$$self{xs}}),
                                 body => $$self{overflow}->sink_gen('O'),
                                 n    => $$self{n},
                                 e    => $type eq 'F' ? '[@_]' : '$_',
                                 v    => 0,
                                 i    => 0},
        q{ %:v = $_;
           %:i = ${%:n} % %@size;
           if (${%:n}++ >= %@size) {
             $_ = ${%:xs}[%:i];
             %@body
           }
           ${%:xs}[%:i] = %:v; };
    } else {
      gen "ring_sink:${type}V", {xs   => $$self{xs},
                                 size => scalar(@{$$self{xs}}),
                                 n    => $$self{n},
                                 e    => $type eq 'F' ? '[@_]' : '$_'},
        q{ ${%:xs}[${%:n}++ % %@size] = %@e; };
    }
  },
};

# Empty source, null sink
defio 'null', sub { +{} },
{
  explain         => sub { '[null io]' },
  supports_writes => sub { 1 },
  source_gen      => sub { gen 'empty', {}, '' },
  sink_gen        => sub { gen "null_sink:$_[1]V", {}, '' },
};

# Sum of multiple IOs
defio 'sum',
sub { [map $_->flatten, @_] },
{
  explain => sub {
    "[sum: " . join(' + ', @{$_[0]}) . "]";
  },

  transform  => sub {
    my ($self, $f) = @_;
    my $x = $f->($self);
    $x eq $self ? ni_sum(map $_->transform($f), @$self)
                : $x;
  },

  flatten    => sub { @{$_[0]} },
  source_gen => sub {
    my ($self, $destination) = @_;
    return gen 'empty', {}, '' unless @$self;
    gen_seq 'sum_source:VV', map $_->source_gen($destination), @$self;
  },
};

# Concatenation of an IO of IOs
defio 'cat',
sub { \$_[0] },
{
  explain => sub {
    "[cat ${$_[0]}]";
  },

  source_gen => sub {
    my ($self, $destination) = @_;
    $$self->source_gen(sink_as {
      my ($type) = @_;
      with_input_type $type,
        gen 'cat_source:OV',
            {dest => $destination},
            q{ $_ > %:dest; }});
  },
};

# Introduces arbitrary indirection into an IO's code stream
defio 'bind',
sub {
  die "code transform must be [description, f]" unless ref $_[1] eq 'ARRAY';
  +{ base => $_[0], code_transform => $_[1] }
},
{
  explain => sub {
    my ($self) = @_;
    "$$self{base} >>= $$self{code_transform}[0]";
  },

  supports_reads  => sub { ${$_[0]}{base}->supports_reads },
  supports_writes => sub { ${$_[0]}{base}->supports_writes },

  transform => sub {
    my ($self, $f) = @_;
    my $x = $f->($self);
    $x eq $self ? ni_bind($$self{base}->transform($f), $$self{code_transform})
                : $x;
  },

  sink_gen => sub {
    my ($self, $type) = @_;
    $$self{code_transform}[1]->($$self{base}, $type);
  },

  source_gen => sub {
    my ($self, $destination) = @_;
    $$self{base}->source_gen(sink_as {
      my ($type) = @_;
      $$self{code_transform}[1]->($destination, $type);
    });
  },

  close => sub { ${$_[0]}{base}->close; $_[0] },
};

# A file-descriptor pipe
defioproxy 'pipe', sub {
  pipe my $out, my $in or die "pipe failed: $!";
  ni_file("[pipe in = " . fileno($in) . ", out = " . fileno($out). "]",
          $out, $in);
};

# Stdin/stdout of an external process with stdin, stdout, neither, or both
# redirected to the specified ios. If you don't specify them, this function
# creates pipes and returns a lazy io wrapping them.
defioproxy 'process', sub {
  my ($command, $stdin_fh, $stdout_fh) = @_;
  my $stdin  = undef;
  my $stdout = undef;

  unless (defined $stdin_fh) {
    $stdin    = ni_pipe();
    $stdin_fh = $stdin->reader_fh;
  }

  unless (defined $stdout_fh) {
    $stdout    = ni_pipe();
    $stdout_fh = $stdout->writer_fh;
  }

  my $pid = undef;
  my $create_process = sub {
    return if defined $pid;
    unless ($pid = fork) {
      close STDIN;  close $stdin->writer_fh  if defined $stdin;
      close STDOUT; close $stdout->reader_fh if defined $stdout;
      dup2 fileno $stdin_fh,  0 or die "dup2 failed: $!";
      dup2 fileno $stdout_fh, 1 or die "dup2 failed: $!";
      exec $command or exit;
    }
  };

  ni_file(
    "[process $command, stdin = $stdin, stdout = $stdout]",
    sub { $create_process->(); defined $stdout ? $stdout->reader_fh : undef },
    sub { $create_process->(); defined $stdin  ? $stdin->writer_fh  : undef });
};

# Filtered through shell processes
defioproxy 'filter', sub {
  my ($base, $read_filter, $write_filter) = @_;
  ni_file(
    "[filter $base, read = $read_filter, write = $write_filter]",
    $base->supports_reads && defined $read_filter
      ? sub {ni_process($read_filter, $base->reader_fh, undef)->reader_fh}
      : undef,
    $base->supports_writes && defined $write_filter
      ? sub {ni_process($write_filter, undef, $base->writer_fh)->writer_fh}
      : undef);
};

}
