// lib/data/models/districts_data.dart
// All 30 Rwanda districts. The schema.sql already seeds these into the
// database. This file provides the same data as a local Dart constant
// so the registration form can populate district dropdowns offline.

import 'models.dart';

const List<DistrictModel> kRwandaDistricts = [
  // Kigali City → Central
  DistrictModel(
    districtName: 'Gasabo',
    province: 'Kigali City',
    region: 'Central',
  ),
  DistrictModel(
    districtName: 'Kicukiro',
    province: 'Kigali City',
    region: 'Central',
  ),
  DistrictModel(
    districtName: 'Nyarugenge',
    province: 'Kigali City',
    region: 'Central',
  ),
  // Eastern
  DistrictModel(
    districtName: 'Bugesera',
    province: 'Eastern Province',
    region: 'Eastern',
  ),
  DistrictModel(
    districtName: 'Gatsibo',
    province: 'Eastern Province',
    region: 'Eastern',
  ),
  DistrictModel(
    districtName: 'Kayonza',
    province: 'Eastern Province',
    region: 'Eastern',
  ),
  DistrictModel(
    districtName: 'Kirehe',
    province: 'Eastern Province',
    region: 'Eastern',
  ),
  DistrictModel(
    districtName: 'Ngoma',
    province: 'Eastern Province',
    region: 'Eastern',
  ),
  DistrictModel(
    districtName: 'Nyagatare',
    province: 'Eastern Province',
    region: 'Eastern',
  ),
  DistrictModel(
    districtName: 'Rwamagana',
    province: 'Eastern Province',
    region: 'Eastern',
  ),
  // Western
  DistrictModel(
    districtName: 'Karongi',
    province: 'Western Province',
    region: 'Western',
  ),
  DistrictModel(
    districtName: 'Ngororero',
    province: 'Western Province',
    region: 'Western',
  ),
  DistrictModel(
    districtName: 'Nyabihu',
    province: 'Western Province',
    region: 'Western',
  ),
  DistrictModel(
    districtName: 'Nyamasheke',
    province: 'Western Province',
    region: 'Western',
  ),
  DistrictModel(
    districtName: 'Rubavu',
    province: 'Western Province',
    region: 'Western',
  ),
  DistrictModel(
    districtName: 'Rusizi',
    province: 'Western Province',
    region: 'Western',
  ),
  DistrictModel(
    districtName: 'Rutsiro',
    province: 'Western Province',
    region: 'Western',
  ),
  // Northern
  DistrictModel(
    districtName: 'Burera',
    province: 'Northern Province',
    region: 'Northern',
  ),
  DistrictModel(
    districtName: 'Gakenke',
    province: 'Northern Province',
    region: 'Northern',
  ),
  DistrictModel(
    districtName: 'Gicumbi',
    province: 'Northern Province',
    region: 'Northern',
  ),
  DistrictModel(
    districtName: 'Musanze',
    province: 'Northern Province',
    region: 'Northern',
  ),
  DistrictModel(
    districtName: 'Rulindo',
    province: 'Northern Province',
    region: 'Northern',
  ),
  // Southern
  DistrictModel(
    districtName: 'Gisagara',
    province: 'Southern Province',
    region: 'Southern',
  ),
  DistrictModel(
    districtName: 'Huye',
    province: 'Southern Province',
    region: 'Southern',
  ),
  DistrictModel(
    districtName: 'Kamonyi',
    province: 'Southern Province',
    region: 'Southern',
  ),
  DistrictModel(
    districtName: 'Muhanga',
    province: 'Southern Province',
    region: 'Southern',
  ),
  DistrictModel(
    districtName: 'Nyamagabe',
    province: 'Southern Province',
    region: 'Southern',
  ),
  DistrictModel(
    districtName: 'Nyanza',
    province: 'Southern Province',
    region: 'Southern',
  ),
  DistrictModel(
    districtName: 'Nyaruguru',
    province: 'Southern Province',
    region: 'Southern',
  ),
  DistrictModel(
    districtName: 'Ruhango',
    province: 'Southern Province',
    region: 'Southern',
  ),
];

String getProvinceForDistrict(String name) => kRwandaDistricts
    .firstWhere(
      (d) => d.districtName.toLowerCase() == name.toLowerCase(),
      orElse: () =>
          const DistrictModel(districtName: '', province: '', region: ''),
    )
    .province;

String getRegionForDistrict(String name) => kRwandaDistricts
    .firstWhere(
      (d) => d.districtName.toLowerCase() == name.toLowerCase(),
      orElse: () =>
          const DistrictModel(districtName: '', province: '', region: ''),
    )
    .region;
