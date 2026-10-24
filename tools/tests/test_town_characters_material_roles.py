"""The tailored waist follows the actual CC0 outfit's authored UV seam."""
from collections import Counter,defaultdict
from copy import deepcopy
import unittest

from tools.town_upgrade.characters.assets import fit_asset,geometry_for,load_asset
from tools.town_upgrade.characters.human import adapted_body
from tools.town_upgrade.characters.manifest import build_manifest


class WardrobeMaterialRoleTests(unittest.TestCase):
    def test_actual_casual_waist_is_one_authored_closed_cycle(self):
        asset=load_asset('clothes','male_casualsuit01');roles=asset['face_roles']
        self.assertEqual(Counter(roles),{'shirt':4006,'pants':4330})
        edge_roles=defaultdict(set);uv_roles=defaultdict(set)
        for face,role in zip(asset['faces'],roles):
            for index,uv_index in face:uv_roles[uv_index].add(role)
            ids=[index for index,_ in face]
            for a,b in zip(ids,ids[1:]+ids[:1]):edge_roles[tuple(sorted((a,b)))].add(role)
        # A material cut through the 2,000-face shirt island fails this check.
        self.assertTrue(all(len(values)==1 for values in uv_roles.values()))
        boundary=[edge for edge,values in edge_roles.items() if len(values)==2]
        self.assertEqual(len(boundary),84)
        neighbors=defaultdict(set)
        for a,b in boundary:neighbors[a].add(b);neighbors[b].add(a)
        self.assertTrue(all(len(values)==2 for values in neighbors.values()))
        visited=set();pending=[next(iter(neighbors))]
        while pending:
            vertex=pending.pop()
            if vertex in visited:continue
            visited.add(vertex);pending.extend(neighbors[vertex]-visited)
        self.assertEqual(len(visited),84)

    def test_partition_preserves_all_source_corners_and_fitted_data(self):
        # The same atlas roles must fit every male casual wearer, including
        # Aria's previously jagged rear hem and the differently adapted elders.
        looks=build_manifest()['characters']
        for key,look in looks.items():
            if look['outfit_asset']!='male_casualsuit01':continue
            with self.subTest(persona=key):
                garment=fit_asset(adapted_body(look),'clothes',look['outfit_asset'])
                before=deepcopy(garment)
                for role in ('shirt','pants'):
                    geometry,weights,ids=geometry_for(garment,role)
                    selected=[face for face,tag in zip(garment['faces'],garment['face_roles']) if tag==role]
                    self.assertEqual(len(selected),len(geometry[1]))
                    for fitted,original in zip(geometry[1],selected):
                        for local,(index,uv_index) in zip(fitted,original):
                            self.assertEqual(ids[local],index)
                            self.assertEqual(geometry[0][local],garment['positions'][index])
                            self.assertEqual(geometry[2][local],garment['uv'][uv_index])
                            self.assertEqual(weights[local],garment['weights'][index])
                self.assertEqual(garment,before)

    def test_roles_are_independent_of_morphed_world_height(self):
        look=build_manifest()['characters']['aria']
        garment=fit_asset(adapted_body(look),'clothes',look['outfit_asset'])
        prior={role:geometry_for(garment,role) for role in ('shirt','pants')}
        garment['unposed']=[(x,y,z+10.) for x,y,z in garment['unposed']]
        for role in prior:self.assertEqual(geometry_for(garment,role),prior[role])


if __name__=='__main__':unittest.main()
