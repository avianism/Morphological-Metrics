#
# ==Introduction
#
# This module contains implementations of the metrics described by Larry
# Polansky in his article _Morphological_ _Metrics_ (_MM_ in this document).
# The abstract of _MM_ introduces the idea of measuring musical distance:
#
# "This article describes a number of methods for measuring morphological
# similarity in music. A variety of _metric_ _equations_ are described which 
# attempt to understand certain kinds of musical and perceptual distances 
# between pairs of shapes in any musical parameter. Different techniques for 
# applying these metrics, such as weightings, variants on each class of 
# metric, and multidimensional and multimetric combinations are also 
# described." _MM_ p. 289
#
# _MM_ defines morphologies, or morphs, as ordered sets. This module treats 
# morphs as 1-dimensional vectors of numerical values, and depends on the
# NArray library for its vector implementation.
#
# The original article and other supporting information can be found on 
# Larry's website: http://eamusic.dartmouth.edu/~larry/mutationsFAQ.html
#
# In addition to the techniques described in _MM_, this module contains tools 
# for generating morphs and sets of morphs which satisfy certain constraints
# regarding their positions in metric space. Though these tools were designed
# with music composition and analysis in mind, they may find application in 
# other areas, such as visual art, computer graphics, psychological experiment 
# design, and the natural sciences. 
#
# ==Simple Usage Examples
# 
# Metrics can be called in a number of ways. The simplest is to prepend 
# "dist_" to the name of the metric you want to call, like so:
#
#  > m = NArray[1,2,3,4]
#  > n = NArray[1,3,5,7]
#  > MM.dist_ocm(m,n)
#  => 0.2777777777777778
#
# This works for all of the metrics defined in this module. However, because 
# some functions (for example, search functions such as 
# @@hill_climb_stochastic) may take a metric as a parameter, metrics 
# themselves are actually defined as class level variables which are procs.
#
#  > MM.ocm
#  => #<Proc:0x00000100947d38@mm.rb:240 (lambda)>
#
# The "dist_" approach described above is syntactic sugar for the following, 
# more direct call:
#
#  > MM.ocm.call(m,n)
#  => 0.2777777777777778
#
# Though the module provides default settings, each of the metrics is 
# configurable with the use of DistConfig objects. The following example
# turns scaling off (metrics use absolute scaling by default):
#
#  > cfg = MM::DistConfig.new({:scale => :none})
#  => #<MM::DistConfig:0x0000010094b320 @scale=:none, [...] >
#  > MM.dist_ocm(m,n,cfg)
#  => 1.6666666666666667
#
# As mentioned above, a number of the methods in this module are generative. 
# That is, they create morphs which fulfill certain constraints concerning 
# their positions in metric space. For example, to find a point a certain
# distance d away from another point v1 given a metric dist_func:
#
#  > MM.find_point_at_distance({:v1 => m, :d => 0.5, :dist_func => MM.ocm})
#  => NArrayfloat4: [ 1.5, 4.0, 1.0, 3.5 ] 
#  > MM.dist_ocm(m,_)
#  => 0.5
#
# Note that as of this writing, this does not always work. Tweaking calls 
# to ensure their plausibility and double-checking the results are both still
# necessary, as these functions do not return warnings when their results
# are sub-optimal:
#
#  MM.find_point_at_distance({:v1 => m, :d => 0.8, :dist_func => MM.ocm})
#  => NArrayfloat4: [ 4.225, 1.275, 4.275, 1.325 ]
#  > MM.dist_ocm(m,_)
#  => 0.5499999999999999
#
#
#  Some current problems:
#    - Right now MM works with Numeric values only. We want it to work with anything.
#    - Related issue: Contour is currently based on the - operator when it should based 
#      on the <=> operator.
#    - The ordered 2-combinations function only operates on one dimension.
#    - Would like to have a nice function for generating N-dimensional spaces with 
#      several local minima and maxima for testing relative performance of search 
#      algorithms.
#    - Search functions should live in their own separate library.
#
#      

$: << File.expand_path(File.dirname(__FILE__) + "/../lib")

require 'mm/helpers.rb'
require 'mm/dist_config.rb'
require 'mm/metrics.rb'

module MM
  include Math
  require 'narray'
  include NMath
  
  #
  # Make each distance metric lambda readable from the outside, i.e.
  # attr_reader behavior, and also provide sugar for avoiding .call
  # (use dist_#{metric}() instead).
  #
  [:euclidean, :olm, :ulm, :ic, :uld, :old, :ocd, :ucd, :ocm, :ucm, :mag, :ucm_2,
   :hill_climb, :hill_climb_stochastic].each do |sym|
    class_eval(<<-EOS, __FILE__, __LINE__)
      unless defined? @@#{sym}
        @@#{sym} = nil
      end

      def self.#{sym}
        @@#{sym}
      end

      def #{sym}
        @@#{sym}
      end
      
      def self.dist_#{sym}(*args)
        @@#{sym}.call(*args)
      end
    EOS
  end

  #
  # Provides the angle between two vectors with respect to the origin or 
  # another vector (v3).
  #
  def self.angle_euclidean(v1, v2, v3 = nil)
    if !v3.nil?
      v1 -= v3
      v2 -= v3
    end
    Math.acos(dot(v1, v2) / (length(v1) * length(v2)))
  end

  #
  # Get the angle between two vectors given a distance function, e.g. one of 
  # the metrics described above.
  #
  # This only makes sense for certain kinds of metrics. At a minimum, the 
  # metric should satisfy the triangle inequality (i.e. it should be a 
  # metric); beyond that, there are other requirements which I do not yet 
  # entirely understand.
  #
  # Question: Should scaling be turned off here by default?
  # Additional question: What does this even mean?
  #
  def self.angle(v1, v2, v3 = nil, dist_func = nil, config = self::DistConfig.new)
    v3 = NArray.int(v1.total).fill!(0) if v3.nil?
    return 0.0 if (v1 == v3 || v2 == v3)      # not sure if this is strictly kosher
    a = dist_func.call(v1, v3, config)
    b = dist_func.call(v2, v3, config)
    c = dist_func.call(v1, v2, config)
    cos_c = (a**2 + b**2 - c**2).to_f / (2 * a * b)
    Math.acos(cos_c)
  end

  # The Euclidean norm of the vector. Its magnitude.
  #--
  # TODO: This probably needs a less confusing name.
  def self.length(v)
    dot(v,v)**0.5
  end

  # The dot product of two vectors.
  def self.dot(v1, v2)
    (v1 * v2).sum
  end

  # Convert degrees to radians.
  def self.deg2rad(d)
    (d * PI) / 180
  end

  # Convert radians to degrees.
  def self.rad2deg(r)
    (180 * r).to_f / PI
  end

  # Simple linear interpolation in Euclidean space
  def self.interpolate(v1, v2, percent = 0.5)
    ((v2.to_f - v1.to_f) * percent.to_f) + v1.to_f
  end
  
  # Get an array of points along a continuous interpolation between v1 and v2
  # with a given sampling interval, specified as a decimal percentage value.
  # So with interval = 0.1, there'd be 11 samples. (0 and 1 are included.)
  def self.interpolate_path(v1, v2, interval)
    raise "Interval must be > 0 and < 1." if interval < 0.0 || interval > 1.0
    percent = 0.0
    path = []
    while percent < 1.0
      path << self.interpolate(v1, v2, percent)
      percent += interval
    end
    path
  end
  
  # Get an array of points along a continuous interpolation between v1 and v2
  # with a sampling interval determined by the total desired number of points.
  # This method will always include the starting and ending points.
  def self.interpolate_steps(v1, v2, num_steps)
    raise "Number of steps must be > 1" if num_steps <= 0.0
    return [v1, v2] if num_steps == 2
    
    interval = 1.0 / (num_steps - 1)
    current_percent = interval
    path = [v1]
    
    (num_steps - 2).times do |step|
      path << self.interpolate(v1, v2, current_percent)
      current_percent += interval
    end
    
    path << v2
    path
  end
  
  # Upsample a vector, adding members using linear interpolation.
  def self.upsample(v1, new_size)
    return v1 if v1.size == new_size
    raise "Upsample can't downsample" if new_size < v1.size

    samples_to_insert = new_size - v1.size
    possible_insertion_indexes = v1.size - 2
    samples_per_insertion_index = Rational(samples_to_insert, possible_insertion_indexes + 1.0)
    
    count      = Rational(0,1)
    prev_count = Rational(0,1)
    hits       = 0
    new_vector = []
    
    0.upto(possible_insertion_indexes) do |i|
      count += samples_per_insertion_index

      int_boundaries_crossed = count.floor - prev_count.floor
      
      if int_boundaries_crossed >= 1
        hits += int_boundaries_crossed
        # next line leaves off the last step of the interpolation
        # because it will be added during the next loop-through
        new_vector.concat(self.interpolate_steps(v1[i], v1[i + 1], 2 + int_boundaries_crossed)[0..-2])
      else
        new_vector << v1[i]
      end
      prev_count = count
    end
    NArray.to_na(new_vector << v1[-1])    # add the last member (which is not an insertion point)
  end

  #######################################################################
  #
  # Generate vectors based on other vectors
  #

  # Uniformly random point on the euclidean unit n-sphere, scale by radius r
  # Approach from: http://mathworld.wolfram.com/HyperspherePointPicking.html
  def self.sphere_rand_euclidean(n, r = 1.0)
    deviates = NArray.float(n).randomn!
    scale = r / ((deviates**2).sum)**0.5
    scale * deviates
  end
  

  #
  # Find v2 a given distance d from v1 using a given metric and search algorithm.
  # Possibly grossly inefficient. Might hang forever.
  #
  def self.find_point_at_distance(opts)
    v1          = opts[:v1]
    d           = opts[:d]
    dist_func   = opts[:dist_func]
    config      = opts[:config]      || self::DistConfig.new
    search_func = opts[:search_func] || @@hill_climb_stochastic
    search_opts = opts[:search_opts] || {}
    allow_duplicates = opts[:allow_duplicates]
    
    if config == :none
      climb_func = ->(test_point) {
        (dist_func.call(v1, test_point) - d).abs
      }
    else
      climb_func = ->(test_point) {
        (dist_func.call(v1, test_point, config) - d).abs
      }
    end
    search_opts[:climb_func] = climb_func
    search_opts[:start_vector] = v1
    begin
      newpoint = search_func.call(search_opts)
    end while (newpoint.to_a.uniq != newpoint.to_a) && !allow_duplicates
    newpoint
  end
  
  #
  # Find a collection of points a given distance from a vector.
  # 
  # Points on the surface of an n-sphere, but these points will 
  # not necessarily be uniformly distributed.
  #
  def self.set_at_distance(opts)
    set_size     = opts[:set_size]     || 10
    max_failures = opts[:max_failures] || 1000
        
    set = []
    failures = 0
    while set.size < set_size && failures < max_failures
      candidate = self.find_point_at_distance(opts)
      if set.include?(candidate)
        failures += 1
      else
        set << candidate
      end
    end
    set
  end
  
  #
  # Create a path of mutants from one vector to another.
  #
  # This path should compromise between directness in the metric
  # space and directness in Euclidean pitch space. 
  #
  # Results may differ dramatically depending on how the distance 
  # metric is scaled! Adjust euclidean_tightness to taste. High tightness
  # values deemphasize metric space in favor of euclidean space. Typical
  # values would be between 0 and 1.
  #
  # When using low tightness values, it may make sense to cheat at the end.
  #
  # Setting euclidean_tightness to 0 and turning cheating off produces
  # interesting results; perfect in metric space, but wildly divergent in 
  # euclidean space.
  #
  # Some other possibilities: make euclidean_tightness a function or array
  # E.g. it could be tight at the beginning and end but stray in the middle
  #
  def self.metric_path(opts)
    v1     = opts[:v1]
    v2     = opts[:v2]
    metric = opts[:metric]
    config = opts[:config] || MM::DistConfig.new
    steps  = opts[:steps]  || 10
    cheat  = opts[:cheat]  || false
    euclidean_tightness = opts[:euclidean_tightness] || 1.0
    allow_duplicates    = opts[:allow_duplicates]    || true
    search_func = opts[:search_func] || MM.hill_climb_stochastic
    search_opts = opts[:search_opts] || {}
    print_stats = opts[:print_stats] || false
    
    total_distance = (config == :none) ? metric.call(v1, v2) : metric.call(v1, v2, config)
    total_euclidean_distance = MM.euclidean.call(v1,v2)
    inc = total_distance.to_f / steps
    
    puts "total_distance: #{total_distance} inc: #{inc}"
    
    path = [v1]
    steps.times do |step|
      i = step + 1
      climb_func = ->(test_point) {
        dist_v1 = (config == :none) ? metric.call(v1, test_point) : metric.call(v1, test_point, config)
        dist_v2 = (config == :none) ? metric.call(v2, test_point) : metric.call(v2, test_point, config)
        target_v1 = inc * i
        target_v2 = total_distance - (inc * i)
        (target_v1 - dist_v1).abs + (target_v2 - dist_v2).abs + (euclidean_tightness * MM.euclidean.call(test_point, MM.interpolate(v1, v2, i.to_f / steps)))
      }
      #puts "\nNew hill climb, starting from #{path[-1].to_a.to_s}"
      search_opts[:climb_func] = climb_func
      search_opts[:start_vector] = path[-1]

      begin
        newpoint = search_func.call(search_opts)
      end while (newpoint.to_a.uniq != newpoint.to_a) && !allow_duplicates
      path << newpoint

      if print_stats && (vectors_at_each_step == 1)
        puts " - newpoint: #{newpoint.to_a.to_s}"
        dist_v1a = (config == :none) ? metric.call(v1, newpoint) : metric.call(v1, newpoint, config)
        dist_v2a = (config == :none) ? metric.call(v2, newpoint) : metric.call(v2, newpoint, config)
        target_v1a = inc * i
        target_v2a = total_distance - (inc * i)
        off_v1a = (target_v1a - dist_v1a).abs
        off_v2a = (target_v2a - dist_v2a).abs
        off_euc = euclidean_tightness * MM.euclidean.call(newpoint, MM.interpolate(v1, v2, i.to_f / steps))
        puts "target_v1: #{target_v1a} target_v2: #{target_v2a}"
        puts "d_v1: #{metric.call(v1, newpoint, config)} d_v2: #{metric.call(v2, newpoint, config)}"
        puts "off_v1: #{off_v1a} off_v2: #{off_v2a} off_euc: #{off_euc}"
        puts "Eval: #{climb_func.call(newpoint)}"
      end
    end
    path[-1] = v2 if cheat    # Because the hill climb doesn't always make it all the way...
    path
  end
  

  # Point on an n-sphere of radius r
  # and angle less than a from vector v

  # Generate a set of vectors with a given mean & sd

  # Given a mean and a vector count, generate a vector or set of vectors which
  # causes the mean to become a given value
  def self.vector_for_desired_mean(current_mean, count, desired_mean)
    total = current_mean * count
    desired_total = desired_mean * (count + 1)
    desired_total - total
  end
  
  
  
  
  ##################################################
  # Search functions 
  #
  
  #
  # Given an array of coordinates and a proc, evaluate every coordinate 
  # using the proc. Returns a hash using coordinate vectors as keys and
  # return values from the proc as values.
  #
  def self.exhaustive(opts)
    coords = opts[:coords] # ranges per dimension
    func   = opts[:func]   # function to evaluate each coordinate

    results = {}
    
    coords.each do |coord|
      results[coord] = func.call(coord)
    end
    results
  end
  
  def self.generate_coords(opts)
    ranges = opts[:ranges] # ranges per dimension
    incs   = opts[:incs]   # increments per dimension
    
    raise ArgumentError, "opts[:ranges].size must equal opts[:incs].size" if (ranges.size != incs.size) 
    
    possible_value_matrix = []
    
    ranges.each_index {|i|
      range = ranges[i]
      inc   = incs[i]
      
      arr = []
      range.step(inc) {|x| arr << x}
      possible_value_matrix << arr
    }
    
    unfold_pvm(possible_value_matrix)
  end
  
  # Helper function for self.generate_coordinates above.
  # Unfold the possible value matrix.
  # I.e., get all the possible combinations of coordinates without repetition.
  def self.unfold_pvm(pvm, partial_coord = [])
    coords = []
    if pvm.length > 1
      bottom_dim = pvm[0]
      new_pvm = pvm[1..-1]
      bottom_dim.each {|dim_value|
        new_partial_coord = partial_coord.clone
        new_partial_coord << dim_value
        coords.concat(unfold_pvm(new_pvm, new_partial_coord))
      }
    elsif pvm.length == 1
      new_coords = []
      bottom_dim = pvm[0]
      bottom_dim.each {|dim_value|
        new_coord = partial_coord.clone
        new_coord << dim_value
        new_coords << new_coord
      }
      return new_coords
    end
    coords
  end
  
  #
  # Naive hill climbing approach. 
  # Create vectors which minimize a given funcion.
  #
  @@hill_climb = ->(opts) {
    climb_func       = opts[:climb_func]
    start_vector     = opts[:start_vector]
    epsilon          = opts[:epsilon]          || 0.01
    min_step_size    = opts[:min_step_size]    || 0.1
    start_step_size  = opts[:start_step_size]  || 1.0
    max_iterations   = opts[:max_iterations]   || 1000
    return_full_path = opts[:return_full_path] || false                  

    start_vector = start_vector.to_f
    dimensions = start_vector.total
    step_size = NArray.float(dimensions).fill!(start_step_size)
    candidates = [-1, 0, 1]
    current_point = start_vector.dup
    path = [start_vector]
    max_iterations.times do |iteration|
      #puts "- Iteration #{iteration}"
      current_point_cache = current_point.dup
      current_result = climb_func.call(current_point)
      (0...dimensions).each do |i|
        #puts "Testing dimension #{i}"
        best_candidate = nil
        best_score = nil
        candidates.each do |candidate|
          current_point[i] += step_size[i] * candidate
          test_score = climb_func.call(current_point)
          #puts "Testing: #{current_point.to_a.to_s}\t\tScore: #{test_score}"
          current_point[i] -= step_size[i] * candidate
          if best_score.nil? || test_score < best_score
            best_score = test_score
            best_candidate = candidate
          end
        end
        if best_candidate == 0 && step_size[i] > min_step_size
          # Coarse movement on this dimension isn't helping, so
          # lower the size...
          step_size[i] = step_size[i] * 0.5
          step_size[i] = min_step_size if step_size[i] < min_step_size
          #puts "Lowering step size on dimension #{i} to #{step_size[i]}..."
        else
          current_point[i] += step_size[i] * best_candidate
        end
      end
      path << current_point.dup
      test_score = climb_func.call(current_point)
      if test_score < (0 + epsilon) && test_score > (0 - epsilon)
        #puts "Success at iteration #{iteration}"
        break
      end
      if current_point == current_point_cache
        # We can't move...
        #puts "Aborting climb at iteration #{iteration} :("
        break
      end
    end
    return path if return_full_path
    current_point
  }
  
  ##
  # :singleton-method: hill_climb_stochastic
  #
  # A stochastic hill climbing algorithm. Probably a bad one.
  #
  # Takes a hash with the following keys:
  #
  # [+:climb_func+] A proc. This is the function the algorithm will attempt 
  #                 to minimize.
  # [+:start_vector+] The starting point of the search.
  # [+:epsilon+] Anything point below this distance will be considered a 
  #              successful search result. Default: 0.01
  # [+:min_step_size+] The minimum step size the search algorithm will use. Default: 0.1
  # [+:start_step_size+] The starting step size. Default: 1.0
  # [+:max_iterations+] The number of steps to take before giving up.
  # [+:return_full_path+] If true, this will return every step in the search.
  # [+:step_size_subtract+] If set to a value, every time the algorithm needs
  #                         to decrease the step size, it will decrement it
  #                         by this value. Otherwise it will divide it by 2.0.
  #
  @@hill_climb_stochastic = ->(opts) {
    climb_func         = opts[:climb_func]
    start_vector       = opts[:start_vector]
    epsilon            = opts[:epsilon]            || 0.01
    min_step_size      = opts[:min_step_size]      || 0.1
    start_step_size    = opts[:start_step_size]    || 1.0
    max_iterations     = opts[:max_iterations]     || 1000
    return_full_path   = opts[:return_full_path]   || false
    step_size_subtract = opts[:step_size_subtract]

    start_vector = start_vector.to_f
    dimensions = start_vector.total
    step_size = start_step_size
    candidates = [-1, 0, 1]
    current_point = start_vector.dup
    path = [start_vector]
    max_iterations.times do |iteration|
      #puts "- Iteration #{iteration}"
      current_point_cache = current_point.dup
      current_result = climb_func.call(current_point)
      # Generate a collection of test points with scores: [point, score]
      test_points = []
      (dimensions * 5).times do |j| # num test points = num dimensions * 3
        # pick a deviation for each dimension
        deviation = NArray.float(dimensions)
        dimensions.times { |d| deviation[d] = candidates.sample * step_size }
        new_point = current_point + deviation
        test_points << [new_point, climb_func.call(new_point)]
      end
      
      test_points.sort_by! { |x| x[1] }
      winner = test_points[0]
      if winner[1] < current_result
        current_point = winner[0] 
        path << current_point.dup
      end
      
      test_score = climb_func.call(current_point)
      if test_score < (0 + epsilon) && test_score > (0 - epsilon)
        #puts "Success at iteration #{iteration}"
        break
      end
      if current_point == current_point_cache && step_size > min_step_size
        # We didn't get any good results, so lower the step size
        if step_size_subtract
          step_size -= step_size_subtract 
        else
          step_size = step_size * 0.5
        end
        step_size = min_step_size if step_size < min_step_size
        #puts "Lower step size to #{step_size}"
      elsif current_point == current_point_cache && step_size <= min_step_size
        # We didn't get any good results, and we can't lower the step size
        #puts "Aborting climb at iteration #{iteration} :("
        break
      end
    end
    return path if return_full_path
    current_point
  }
  
  
end
