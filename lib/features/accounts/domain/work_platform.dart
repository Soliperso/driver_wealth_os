enum WorkPlatform {
  uber('uber', 'Uber', 'Rides & delivery'),
  // Distinct from Uber: a driver's economics on delivery and rides are not the
  // same, and the backend reports them under separate employer names.
  uberEats('uber_eats', 'Uber Eats', 'Delivery'),
  lyft('lyft', 'Lyft', 'Rideshare'),
  doorDash('doordash', 'DoorDash', 'Delivery'),
  instacart('instacart', 'Instacart', 'Shopping & delivery'),
  grubhub('grubhub', 'Grubhub', 'Delivery'),
  amazonFlex('amazon_flex', 'Amazon Flex', 'Delivery'),
  walmartSpark('walmart_spark', 'Walmart Spark', 'Delivery'),
  other('other', 'Other', 'Other work');

  const WorkPlatform(this.id, this.displayName, this.category);

  final String id;
  final String displayName;
  final String category;

  static const connectable = [
    uber,
    uberEats,
    lyft,
    doorDash,
    instacart,
    grubhub,
    amazonFlex,
    walmartSpark,
  ];
}
