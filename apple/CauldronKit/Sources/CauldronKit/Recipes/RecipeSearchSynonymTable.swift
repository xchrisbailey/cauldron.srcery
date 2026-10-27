extension RecipeSearchSynonyms {
  /// The names search knows by default: UK and US words, trade names and common respellings
  /// too far from the word to be a typo. Hand-written; a group is a line, and a name appears in
  /// one group only. To add one, add a name to a group or a line.
  public static let standard = RecipeSearchSynonyms(groups: [
    // Vegetables and herbs.
    ["aubergine", "eggplant"],
    ["courgette", "zucchini"],
    ["coriander", "cilantro"],
    ["rocket", "arugula"],
    ["spring onion", "scallion", "green onion"],
    ["capsicum", "bell pepper"],
    ["chilli", "chili", "chile"],
    ["beetroot", "beet"],
    ["swede", "rutabaga"],
    ["mangetout", "snow pea"],
    ["pak choi", "bok choy"],
    // Meat, fish and pulses.
    ["mince", "ground beef"],
    ["prawn", "shrimp"],
    ["broad bean", "fava bean"],
    ["chickpea", "garbanzo"],
    ["haricot", "navy bean"],
    // Baking and the pantry.
    ["cornflour", "cornstarch"],
    ["plain flour", "all-purpose flour"],
    ["self-raising", "self-rising"],
    ["icing sugar", "powdered sugar", "confectioners sugar"],
    ["caster sugar", "superfine sugar"],
    ["double cream", "heavy cream"],
    ["single cream", "light cream"],
    ["bicarbonate of soda", "baking soda"],
    ["golden syrup", "corn syrup"],
    ["treacle", "molasses"],
    ["yoghurt", "yogurt"],
    ["ketchup", "catsup"],
    ["filo", "phyllo"],
    // Dishes and courses.
    ["biscuit", "cookie"],
    ["crisps", "chips"],
    ["jam", "jelly"],
    ["porridge", "oatmeal", "oats"],
    ["pudding", "dessert"],
    ["starter", "appetiser", "appetizer"],
    ["main", "entree"],
    ["aubergine parmigiana", "eggplant parmesan"],
    ["spring roll", "egg roll"],
    ["donut", "doughnut"],
    ["lasagne", "lasagna"],
    ["houmous", "hummus"],
    // Respellings too far from the word for a typo to reach.
    ["kimchee", "kimchi"],
    ["overnite", "overnight"],
    ["sriracha", "siracha"],
  ])
}
