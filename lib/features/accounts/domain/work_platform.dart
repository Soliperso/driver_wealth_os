enum WorkPlatform {
  uber('uber', 'Uber', 'Rides & delivery'),
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
    lyft,
    doorDash,
    instacart,
    grubhub,
    amazonFlex,
    walmartSpark,
  ];
}
