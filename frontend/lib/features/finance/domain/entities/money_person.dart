class MoneyPerson {
  const MoneyPerson(this.id, this.name, this.group);
  final String id, name, group;
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'group': group};
  factory MoneyPerson.fromJson(Map<String, dynamic> j) => MoneyPerson(j['id'], j['name'], j['group'] ?? 'Cá nhân');
}
