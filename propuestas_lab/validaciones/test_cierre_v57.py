"""Pruebas de decisión del cierre V5.7 (modelo local, no RPC ni BD)."""
def evaluate(inning, top, ended, home, away, regulation=6, super_margin=15, knockout=10):
    lead=home-away
    threshold=super_margin if inning==3 else knockout if inning>=4 else None
    if threshold and ((top and ended and lead>=threshold) or (not top and (lead>=threshold or (ended and lead<=-threshold)))):
        return 'Súper knockout' if inning==3 else 'Knockout'
    if inning>=regulation and ((top and ended and lead>0) or (not top and (lead>0 or (ended and lead<0)))):
        return 'Final reglamentario'
    return None

cases=[
 ('sin nocaut en segunda',2,False,True,20,0,None),
 ('supernocaut 15 alta tercera completa',3,True,True,15,0,'Súper knockout'),
 ('supernocaut 14 no basta',3,True,True,14,0,None),
 ('visitante 15 alta tercera: local debe batear',3,True,True,0,15,None),
 ('visitante 15 baja tercera terminada',3,False,True,0,15,'Súper knockout'),
 ('local 15 baja tercera inmediata',3,False,False,15,0,'Súper knockout'),
 ('nocaut 10 alta cuarta terminada',4,True,True,10,0,'Knockout'),
 ('nocaut 9 no basta',4,True,True,9,0,None),
 ('visitante 10 alta cuarta no basta',4,True,True,0,10,None),
 ('visitante 10 baja cuarta terminada',4,False,True,0,10,'Knockout'),
 ('nocaut 10 en quinta',5,False,False,10,0,'Knockout'),
 ('local gana al terminar alta sexta',6,True,True,4,3,'Final reglamentario'),
 ('alta sexta empatada',6,True,True,4,4,None),
 ('visitante gana alta sexta: falta baja',6,True,True,3,4,None),
 ('visitante gana tras baja sexta',6,False,True,3,4,'Final reglamentario'),
 ('local gana durante baja sexta',6,False,False,4,3,'Final reglamentario'),
 ('empate tras baja sexta: extras',6,False,True,4,4,None),
 ('local gana en extra',7,False,False,5,4,'Final reglamentario'),
]
for name,inning,top,ended,home,away,expected in cases:
    actual=evaluate(inning,top,ended,home,away)
    assert actual==expected, f'{name}: esperado {expected!r}, obtenido {actual!r}'
print(f'{len(cases)} casos de lógica de cierre V5.7 correctos (modelo local).')
