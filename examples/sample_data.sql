--
-- PostgreSQL database dump
--

-- Dumped from database version 16.6
-- Dumped by pg_dump version 16.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: user; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public."user" VALUES ('U286f94380611', '2024-09-28 06:56:52.987102+00', '2025-02-15 21:35:05.080308+00', 'Thorin Oakenshield', 'Son of Thrain, son of Thror, King under the Mountain', true, 'iqjH7nwdD1CBa-XgaW90yY443ghL8RC0Za-hKv-aeGg', 512, 341, '-HB2.D%20$Ip-U%1$koLEgR*s:t6I=WV%1WVNGRk5RNG-TxZI:Rk9]WC-TxZWVS3oyj[WBoLofj[t6a}RkafkCoyj[oeoej[aeRk');
INSERT INTO public."user" VALUES ('Ub8eac19792cf', '2024-10-05 09:32:59.765721+00', '2025-02-15 21:34:57.450945+00', 'Bifur', 'the cousin of Bofur. and Bombur', true, 'l1mOfrth3gUfWSY5rbxmObwsntPdZ2-AB4SIrF9yRhU', 520, 432, '-8A0?:4mIo%M~WXSe9%hXTaK?HM_RiRP-=t7M_oepJWB$iR*I:t7IUxv%2RjIon%R%M{%MayM{j@V@t7WBoLkCof%gRibHt7WAog');
INSERT INTO public."user" VALUES ('U0679e218a6e4', '2024-10-05 09:34:07.492171+00', '2025-02-15 21:35:07.59938+00', 'Bofur', 'the brother of Bombur', true, 'gIQj6htpAzZEJKzrbE6yc0QjVh5UI9j70OaKBuSL3p4', 450, 600, 'q37wjBEN16^kn,I:E1=|A0xaV?j]-6Iobbs:bFs:V@NGt7s.WEoeI:bI-UR%5R-U%1ELEMoMxZWUjFoft7I;jHs.WVNHsnofW=s.');
INSERT INTO public."user" VALUES ('U6301c73d1354', '2024-10-05 09:37:53.81252+00', '2025-02-15 21:35:53.149769+00', 'Kíli, grandson of Thrain', 'Honestly, who cares if she wasn’t in the book? You can’t control what your heart wants, and neither can the guy writing the script!', true, 'QJo5eb91CFxMz-EtClqwY6V2sT5YmK1BxlXm682uKjo', 399, 270, '-F9?n0%L0fM{-o-o?GxaIpV[t6t7E2WC%1xtR*Ip9aRj-o%2WBIpE2jZ%1kCafjZkBofWBNGWVs:xaj[aeR*Naoft6ofayR*WVs:');
INSERT INTO public."user" VALUES ('Ud5a151749e32', '2024-10-05 09:35:03.214096+00', '2025-02-15 21:36:11.539499+00', 'Bombur', 'the brother of Bofur', true, 'M7CkS7IGY6HRqKbQZqKC6ZiIDqovRfa6qisRJiFgYVQ', 520, 432, '-EBys*-pOrWB%2bJ~XoftRNHkDoex^Iof9WBNFWBNbRjxaxZWAoeW=aen$t7WBofxaayM{s:WBR*X9WBRioffjWBtRkCRjays:WB');
INSERT INTO public."user" VALUES ('U8ebde6fbfd3f', '2024-10-05 09:38:59.994397+00', '2025-02-15 21:36:20.435288+00', 'Dain Ironfoot', 'CEO of Ironfoot Industries and the Lord of the Iron Hills. Veteran in resource extraction and heavy manufacturing. When the chips are down, I’m the guy you want in your corner. Tough decisions? I make them every day. 👊 Always looking for the next big opportunity in heavy industry and infrastructure.', true, '60qBqhlXQzNOvlgK9h1FdxzpZX18EcC2A-6vqr_ABu8', 425, 600, 'qECY,UodSz~BX8M{xZn$-p%1xt%1s,oc$%WXV@RjM|R*ayoexaofI;NGIpNHR+kCj[R*D*R-NbNGNHkCbHWXIokCkCNGa}ofoeoe');
INSERT INTO public."user" VALUES ('U2d94f2dd547e', '2024-10-05 09:30:51.974479+00', '2025-02-15 21:36:40.563009+00', 'Nori', 'a distant relative', true, 'z08GtdyVM-UC-486_6O2ijx3xugBqpVci_2l1vlZ6ck', 768, 528, '-57,}iRj11-o=xof-Vbb9]WA$$WBE2bcIpWVxuM|M{s9={WBI:xaE*WB=wX8EMs:0zW=-VR*ELj[R+xG$io0R*R*t7oKj[azoKj]');
INSERT INTO public."user" VALUES ('Ud14e4cfed365', '2024-10-05 09:43:07.136677+00', '2025-02-15 21:36:42.028916+00', 'Galadriel', 'Founder of Lothlórien Ventures. Empowering visionary startups and fostering sustainable innovations for a brighter future. 🌿 Known for wisdom, foresight, and a deep commitment to shaping the world we leave behind. I see potential where others see risk.', true, 'vcMRwhgYTO6IaEoIs9sT7WIY6wH6fpMKpc5qdEosboM', 332, 599, 'qC5$@?RQL#M{X-yDH?tRQ.ozMwaK%#V[n%M_tloyWCaxR5o}o#aLn4WUo}VsRPtRWBt8M_ofj]ozt7RPtSRPxaWCtRRPMxt7kCxu');
INSERT INTO public."user" VALUES ('U15f925d86858', '2024-10-05 09:28:58.721013+00', '2025-02-15 21:35:52.49314+00', 'Dori', 'a distant relative', true, 'UbfwizEOjvTZoyxq0JjxflAf_aNWZnXtC7sX259r7II', 450, 600, 'q97A#sRj0z%2=xELIp-U=|WX9ts:-VM|I:%1xZazNGoKxaWXR*j[Rkj@s:WCR+ofoKR*I:oLxZR+Nas:snR*NHoLxZWCNas.soS2');
INSERT INTO public."user" VALUES ('U2becfc64c13b', '2024-10-05 08:40:11.960998+00', '2025-02-15 21:35:00.729221+00', 'Gandalf the Gray', 'Experienced business angel and startup mentor with a knack for turning risky ventures into legendary success stories. Disrupting the market since before it was cool. Occasionally disappear to let teams find their own path, but always return at the right moment. DM for networking and strategic advice.', true, 'DpywC3XZqDJFLyey0w11Ms1dX2I1RWgEl5Ps-tONuo8', 756, 600, '-#G+adIU%MozWBWB~qj?xuj[WBWV?bj[jsozRjayxut7RjofWBWBWBxtRkWBt7WBjZayWBWBt7f6WBWBRkWBofofofRjaeWBfQt7');
INSERT INTO public."user" VALUES ('Uffbd6f094f6a', '2024-10-05 09:27:54.591733+00', '2025-02-15 21:35:03.568563+00', 'Ori', 'a distant relative', true, 'pXKcrTAZQiRYcm4O3DyGFR04bBWcfz_25YetINbG2nw', 449, 600, 'q77^iJE20~^j$gEMR*-UV@ofI:ni$gI;WVxaE1s:$%NHX8s.bIR*OYae$iNwI:-Un%IpELt6%1NGR*xZs:R*WVa|jZs:fkRkoes:');
INSERT INTO public."user" VALUES ('U41906748a800', '2024-10-05 09:03:25.530928+00', '2025-02-15 21:35:11.615625+00', 'Smaug the Golden, the Impenet...', 'Curse your input limits, worms! Behold Smaug the Golden, the Impenetrable, and the Terrible!



Serial investor, crypto whale, and guardian of one of the largest digital asset hoards in the world. I believe in the power of scarcity, and I’m not sharing. 🐉 Looking for high returns and total market domination. If you come for my assets, be prepared to face the fire. My armour is like tenfold shields, my teeth are swords, my claws spears, the shock of my tail is a thunderbolt, my wings a hurricane, and my breath death!', true, 'y3UATslnQleM_jX1LuuL61j4mjpq2CU3ATyw8xCEJss', 315, 600, 'qPB_;yIo0~%2wINIxtjEOsRj$gxaI:R+xaRkI;so$$NcWXxEWCS4rqt7NwM|$*s.NGofIokWxZaJozSgRjs:s9kCS5WAofWXWBs:');
INSERT INTO public."user" VALUES ('Ub0100d7bad5f', '2024-10-05 09:24:15.200053+00', '2025-02-15 21:35:15.50218+00', 'Dwalin', 'Son of Fundin', true, 'jQS0sNLnLzdWi2MDYKR3Gvxt_ajeJ8CVSHZLt1E_HE4', 742, 600, '-D9Q22M|0g={={Io^iR+0g%1={Io-oWWIpR+oeafRjs:xZRkt6xZR*t6xZRkWBs:NHR+bHWCR+S4R*oet6afaykCM|s.%1WBRkxa');
INSERT INTO public."user" VALUES ('Udab52ec61933', '2024-10-05 09:26:35.635519+00', '2025-02-15 21:35:17.194461+00', 'Glóin', 'Son of Groin', true, 'lf_zWksLjjO4wGwudQVQ5XLP84k8cutvEYyAf5K8veU', 479, 398, '-8A,Ri~W.9N_^,W=~WkWpJf+~W^+?IM{RjIoM{RjE0D%j]MxE0M{9ZE0xG%2IoofS1xa%3t7IUNGM{M{oLs;RjR*NGInV@adV@ay');
INSERT INTO public."user" VALUES ('U7aa6bd888278', '2024-10-03 07:57:43.015692+00', '2025-02-15 21:35:39.712604+00', 'Balin', 'Son of Fundin, (spoiler alert!) Lord of Moria.', true, 'TtWeX7akyYn5bOtzZIjKZgDFCdCie6Co7bOqfMBY-OA', 260, 194, '-NE2a=9Z0f-ojFbbWCxuELj]oJR*IpjZ$*R*t7aebuRjsobFazt6E1xus:NGofWBa#WBs:WWofazM{j[xaoLR*f6s:R*j[oeWBa}');
INSERT INTO public."user" VALUES ('U4d9267c70eab', '2024-10-05 08:48:39.912918+00', '2025-02-06 20:55:34.534532+00', 'The Anonymous of Dol Guldur', 'Let''s save the nature and cultural traditions of Middle-earth! 



Activist, publicist, concerned neighbor and representative of one of the largest communities in Middle-earth.', false, '0E_W6fNl_e9zk-YtRWlHTNVQnTBkxK2csCtfkdxeCVc', 0, 0, '');
INSERT INTO public."user" VALUES ('U3a33697ffab9', '2024-10-05 07:29:28.580198+00', '2025-02-15 21:35:43.579423+00', 'Bilbo Baggins', 'Well I do have some skill at conkers, if you must know. I am Baggins of Bag-end!', true, 'XO7NOCNL8Y7N_2Tjg-lGRnMbCssN2aP_BIqucFgroGc', 387, 600, 'q55hDN%20fE1-o-poLIUM|ayofbHjFniWqbv56Rk?G%2IpIoj[xukDj[enadg3kXaeVs%1j[NGays.WCj[oeRjWCozofjFaKWqkW');
INSERT INTO public."user" VALUES ('U050e67479957', '2024-10-05 09:35:59.865028+00', '2025-02-15 21:35:57.89741+00', 'Fíli, grandson of Thrain', 'I don’t always take risks, but when I do, I make sure they’re epic!', true, 'xccTTJFOI2lc3hhnaA9wqnXwMruWAdSpMWCHpeBjkCQ', 695, 600, '-VFO.J^%OFENoM%M~W-nW=NIWAxutRRiWCjYV@WBofWCbIj]V@RjRkWXt7kCkBRks:W=WCj[j?fPaykCWBj@oeRjR*WYjYoLbHWB');
INSERT INTO public."user" VALUES ('U8c85f8c3bef7', '2024-10-01 07:28:11.348856+00', '2025-02-15 21:36:06.987834+00', 'Thrush', ':trollface:', true, 'VE_Zc_dFAC9gv0SHFgO0ZxHItxln6HfNKmfSQhVeCqA', 350, 600, 'q37_1ZMd589G%1%MNHog9a01Wq%2-pkCM|t7O@%g=^-oIpIpaeWA0LMx$ybbIpWBxZt6^*?aIp9bj?%0xZRkrqIVE3V@-Un$S5NH');
INSERT INTO public."user" VALUES ('Ue479f7b03b5d', '2024-10-05 09:00:32.373065+00', '2025-02-15 21:36:24.827792+00', 'Bard the Bowman', 'Cargo transportation, logistics, dragon slaying.', true, '1zZZ-U5rjbGJ4qfsqAtiVizWv7B-1gCnymUahzNiKGY', 430, 600, 'qRFFA]-.~U%Loft7WXj[I[t7bIWYxta#j]a#WCM|IWoJNHs.t6oeRjWAjYRkoeWCR*j@M}oeIpayjZf6oJWCM|WBM|oJRkjsWBWC');
INSERT INTO public."user" VALUES ('U28846d74623d', '2024-10-05 09:25:25.397125+00', '2025-02-15 21:36:29.269434+00', 'Óin', 'Son of Groin', true, 'F1RP3K5rrRSkvYnPJsC1wEJig4U-qly6GiaMnJUdRD4', 510, 506, '-KCi:j9ZtRjF-qIo~XM{o}sojYRjxut7NGxaRjkCozj[jYWBWBt7WVWAn%R*WBaxWXj[aeWVWBofogfPf6j[aya|WBj[oeWBj[of');
INSERT INTO public."user" VALUES ('Ue79d43c03425', '2024-10-05 09:09:59.48232+00', '2025-02-15 21:36:34.901727+00', 'Radagast the Brown', 'Founder of NatureFirst, a green tech startup focused on sustainable solutions and biodiversity preservation. Advocate for the natural world, tech enthusiast, and occasional caregiver for wild creatures. I believe technology can harmonize with nature—if we only listen to the trees.', true, '66V8Vnnaq1q-JeiOzdgXEG4Lmjqd2c3_JRoCRzhggNw', 513, 600, 'q87e06_MpHOBoyt6kBfiggtQtR%LtPxsxttQx]tRnlaeR*R*jYoex[ozf,a$ofoLWCWBxut8NIRkWBaeRkWWX8WXRkRkayRjRjRj');
INSERT INTO public."user" VALUES ('U36906cde6568', '2024-10-05 09:46:32.2244+00', '2025-02-15 21:35:28.319369+00', 'Smeagol', '"""You Don’t Have Any Friends. Nobody Likes You!""

""Not listening. Not listening""

""You are a lier, a thief""

""Nope""

""Muuurderer"""', true, 'YBp-JQjyVDTCMSXS_nk36mXxWs151XFlidGLpHhd8Cg', 420, 560, 'qA6[,LMw4Tn,nht,aJj@x^yDH?IAxuozo}jFDix^x]DiWCxuo}aztQMyxvxuIAt7xaS2R5WBjF%gW;MexuayDini%gWVtQRQMxx]');
INSERT INTO public."user" VALUES ('U54c3f9996693', '2024-10-05 09:45:15.503243+00', '2025-02-15 21:36:13.273019+00', 'Legolas', 'EZ game, EZ life, let me solo them', true, 'gmzJvThatWbPk5R6kKqRmTktVN7IyWYq9XIfJRmfiX8', 340, 600, 'qGCPq$009_rpxaSg%LM|nlfiIot7?GE1IoxtIo%MMxozozRiogt6-;M{afbFkDoKj[R*RjozRPt8ofRkRjofbHofRjt7R*jZoLkC');
INSERT INTO public."user" VALUES ('U3ffe5ced51de', '2024-10-05 09:44:05.557361+00', '2025-02-15 21:36:18.34938+00', 'King Thranduil', 'Preserving the elegance of nature and culture is not just a task; it''s an art. 🌿 Join me in cultivating a future where beauty and sustainability go hand in hand.', true, 'RviugAYfCFbMIddeFa1_dOocfkZkWZrXrAS43cDEdOE', 598, 562, '-HEUoi%L0#9ai_%1E1a0Naoy-UofS5Nx-TsmJ8Rko|WBi_WBNbf+R-S4xa$%NGNHIoNGoekCofjZt7t7t7fPjYRkRjRjoLWXRks.');
INSERT INTO public."user" VALUES ('Ub13c4a82ab30', '2024-10-05 09:42:01.875298+00', '2025-02-15 21:36:27.059451+00', 'Saruman the White', 'Orthanc Innovations. 

Ransforming the world through AI and cutting-edge technology. Once a believer in collaboration, now focused on ultimate control and market dominance. ⚙️ There is only one future, and I intend to shape it. Open to discussions... for those who understand the bigger picture.', true, 'pc2EjCSTTIDP4E9mpYfUca_Dndp-6yRuS-iP1A23StA', 450, 600, 'qMFYidIV0K%2I9W9jEjY4nkWNH%M-qITj[RPx]V@%2fkR*RkIUxvInofaKRjR*s:xuozIUs:xuRjozogoLWVM{WBt7RjRjxuj[og');


--
-- Data for Name: beacon; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.beacon VALUES ('B4342c0e949fb', '2024-10-03 07:07:28.469578+00', '2024-10-03 07:07:28.469578+00', 'U8c85f8c3bef7', 'knock-knock-knock', '', NULL, true, false, NULL, NULL, NULL, 0, 0, '');
INSERT INTO public.beacon VALUES ('B6d130d7414d1', '2024-10-03 07:08:57.723265+00', '2024-10-03 07:08:57.723265+00', 'U8c85f8c3bef7', 'Knock-Knock-Knock', '', NULL, true, false, NULL, NULL, NULL, 0, 0, '');
INSERT INTO public.beacon VALUES ('B988f628fa22f', '2024-10-03 07:09:11.26565+00', '2024-10-03 07:09:11.26565+00', 'U8c85f8c3bef7', 'KNOCK-KNOCK-KNOCK', '', NULL, true, false, NULL, NULL, NULL, 0, 0, '');
INSERT INTO public.beacon VALUES ('B0cb05535835f', '2024-10-05 08:44:54.558388+00', '2024-10-05 08:44:54.558388+00', 'U2becfc64c13b', 'A Feast for Our Dwarven Friends', 'Greetings, esteemed allies! I’m excited to share that I’ve just finalized plans with Elrond for a grand charity dinner dedicated to our valiant dwarven companions. We’ll gather to celebrate their courage, share tales of bravery, and, of course, raise funds for their upcoming endeavors.



Additionally, I’ll be providing a strategic consultation on navigating the intricacies of our map—after all, it’s not just about the journey but knowing where to tread wisely. Looking forward to an evening filled with camaraderie and purpose!

', NULL, true, false, NULL, NULL, 'QuestForGlory', 0, 0, '');
INSERT INTO public.beacon VALUES ('Bc1cb783b0159', '2024-10-03 07:10:52.490647+00', '2025-02-15 21:36:46.86133+00', 'U286f94380611', 'The Quest for Glory Awaits!', 'Durin''s Kin, our noble company seeks valiant souls to join us in our grand endeavor to reclaim the Lonely Mountain from the vile Smaug. If you possess the heart of a true dwarf and the mettle to face fire and darkness, we welcome your blade and your courage. Our quest is not for the faint-hearted, but for those who yearn for honor and glory.



Requirements:

 – Expertise with axe or sword

 – An appreciation for fine gold and gemcraft

 – A robust constitution to withstand dragon fire and goblin ambushes



If you are bold enough to stand among dwarves of valor, reply to this call or send a raven. Please, only those who are committed to the cause and not easily deterred by peril. And kindly, leave behind those who speak only of their uncles’ exaggerated tales of elvish grandeur. Our journey is fraught with danger, but for those who stand with us, there is a treasure beyond dreams and tales of heroism.

', '["2024-10-03 00:00:00+00","2025-10-03 00:00:00+00"]', true, true, NULL, NULL, 'QuestForGlory', 337, 600, 'q9DTa-Dk={_L-o?tHtRQRQM{r?4p%foxyB%LV@RjNHj[s.M|s:WBIVs:x@x[WDxtafV[%LofWERjV[RkM|V@RRWBVtayW;j@tjWC');
INSERT INTO public.beacon VALUES ('B521ff7422d52', '2024-10-03 07:43:51.47572+00', '2025-02-15 21:36:56.313698+00', 'U286f94380611', 'A Call to the People of Esgaroth', 'People of Esgaroth, hear the words of Thorin Oakenshield, heir to the Kingdom of Erebor, rightful King Under the Mountain! I stand before you not only as a dwarf of noble blood, but as one who offers you an opportunity like no other.



The Lonely Mountain, long lost to our kin, still holds untold riches—gold, gems, and treasures beyond the wildest dreams of Men. Yet these riches lie in the grip of a vile dragon, Smaug, who has grown fat and careless in his slumber. With courage and support, we will reclaim what is ours, and those who aid us will share in the bounty.



I call upon you, brave and resourceful people of Esgaroth, to stand with us. Your provisions, your tools, your ships to speed us on our way—these will all be repaid in full, many times over, when the treasure is divided. The wealth of Erebor is vast, and those who help restore its rightful King shall receive a fortune beyond imagination.



The path is not without danger, yet fortune favors the bold. Let us stand together, and soon the halls of Erebor will sing again with the voices of prosperity.



Will you seize this moment, or let it pass into the hands of those more daring? Choose wisely, for this is no ordinary venture, but the reclaiming of a kingdom, and with it, the future of all who aid in its restoration.

Stand with us, and be remembered not just for your courage, but for the wealth you will pass down to your children''s children.', NULL, true, true, NULL, NULL, 'QuestForGlory', 1066, 600, '-rKw|FjFxttQWVWBjbMyofofWBt701t7xut6oeoLozofWBoJWBt7oyWBaykBt6juoKs:RjkCofay%LWBWBj[WVRkj[ayt7f6ayR*');
INSERT INTO public.beacon VALUES ('B86a6e5de190a', '2024-10-05 08:10:18.923486+00', '2025-02-15 21:37:43.764487+00', 'U3a33697ffab9', 'Dragon''s Curse? Your Thoughts?', 'Hello, wise folks of the internet! I could really use some advice here. We’ve stumbled upon this incredibly shiny (and probably cursed) gem called the Arkenstone, and things have been a bit... tense. 😬 You see, ever since Thorin got his hands on it, the mood has shifted. A lot. And not in a good way.



Now, I’m no expert, but I’ve heard rumors of something called "dragon sickness"—apparently, being around a dragon’s hoard for too long can really mess with your head. And, well... let’s just say Thorin and the other dwarves are showing symptoms (greed, paranoia, slightly worrying speeches about reclaiming their kingdom by any means necessary 😳).



So, I need your help! Has anyone heard of this before? Is there any way to cure this dragon hoard fever? Or is it just a side effect of having way too much gold around? 🤔



💬 Poll:

1) It’s the Arkenstone! Definitely cursed. 🔮

2) Dragon sickness is real—get those dwarves some fresh air, stat! 🐉💨

3) Gold fever? Maybe Thorin’s just had one too many ambitious ideas. 💰

4) Not sure, but this sounds like something a good cup of tea might help with. 🫖😌



Also, if you have any experience with dragons, magical gems, or dealing with very stubborn dwarves, please drop some advice in the comments. I’m open to any tips, tricks, or even tactful ways to say, “Thorin, maybe it’s time to take a break?” 🫤



Thanks in advance—let’s hope we can get this sorted before someone does something rash (like trying to start a war or swimming in piles of gold... again). 😅

', '["2024-10-05 00:00:00+00","2025-09-30 00:00:00+00"]', true, true, 9.986161294301063, -9.140625000000002, 'Community Support', 600, 600, ':355LP?HJ79tM{xGV@WB~V%MoyM{M|aeWAWBNboz$*-pRjIVRjNGIpbI%2-pjbM|M{Ioj[xuofs:xuNGM|Rj-p%2j[R*WVRjWBad-p%2t7NGM|WVRjs.-p%2ofRjRjaeWBRj');
INSERT INTO public.beacon VALUES ('Bb4dbbb63b373', '2024-10-05 07:58:55.882967+00', '2025-02-15 21:37:45.93333+00', 'U3a33697ffab9', 'The Сharm of Elves and Wine', 'Friends, travelers, and those who appreciate the finer things in life—have I got a treat for you! During my eventful adventures (which I’m still processing, by the way 😅), I’ve had the chance to visit the most extraordinary vineyard, run by none other than the Elvenking Thranduil himself. Yes, you read that right—elves make wine, and let me tell you, they know what they’re doing! 🍇✨



But it’s not just about the incredible flavor (which is out of this world, seriously). Thranduil’s winery is all about sustainability. Zero waste. That’s right: nothing goes to waste, not even a grape stem. 🍃🍇



Here’s why you’ll want to raise a glass to this:

🌱 Zero Waste: Every part of the winemaking process is designed to be eco-friendly. From the vines to the bottle, Thranduil''s elves ensure nothing gets thrown away. Even the barrels are crafted with care to last centuries! ♻️

🍇 Organic, Naturally: No harmful chemicals, no artificial anything—just pure, elven-grown grapes and the magic of the forest. 🌿✨

💧 Elven Precision: With their unmatched craftsmanship, the elves have created a process that uses 80% less water than traditional methods. Save the forest, sip some wine!

📦 Reusable Packaging: Bring your bottle back, and they’ll refill it (and you’ll get a discount too! 💰). It’s all about keeping the forest and rivers clean.



If you want to support eco-friendly practices and enjoy what might just be the best wine in Middle-earth, head over to Thranduil’s Vineyard. Drink responsibly, save the world one glass at a time, and help spread the word—this is the kind of business we should all get behind!



Now, if you’ll excuse me, I have another bottle to finish. 😏🍷

', NULL, true, true, NULL, NULL, 'There and Back Again', 337, 600, 'q76%.p$%Nd%0xYWWNIoL0ioexYNHR+j[xYoK%0ENENoKjZayWCazs:-T$%s.oeWCayfQR+NbkBWCR+oKoeazWVIqIqsns.WWR+W;');
INSERT INTO public.beacon VALUES ('B0055751ce4cc', '2024-10-03 07:51:18.689543+00', '2025-02-15 21:36:51.01036+00', 'U286f94380611', 'A Triumph Realized!', 'It is with the greatest honor that I, Thorin Oakenshield, rightful King Under the Mountain, proclaim the resounding success of our noble quest. Erebor is ours, and the riches that lay dormant beneath its stone halls now flow once again, filling the coffers of those who stood beside us.



To my steadfast company, who braved dragon fire and peril without faltering, your loyalty shall be rewarded beyond measure. Dividends from our treasure hoard will be distributed shortly to all who share in our victory. You, who proved your worth with axe and sword, shall bask in the wealth of the Mountain.



As for the rest—those who stood idle in our hour of need, the so-called allies who now seek a portion of our hard-won riches—they shall have nothing. Let it be known: neither Men nor Elves shall lay claim to a single coin of what is rightfully ours. Let them speak of their grievances to the wind, for it is all they shall receive.



"Will you have peace, or war?" you dare to ask? There is my answer: I will have war!', NULL, true, true, NULL, NULL, 'QuestForGlory', 600, 600, ':A8:;S58J5NI?FNHIp%1~AE3WTRn%1R*RkxZI=oJxGbHNHo0s.R+9b%0V]xaNHjZs.R+RlxsIpxsjaNHofs:s:oeIqt6s:Rkjtt6j[f6WVWCofo0WCfkNHoJofWVWWs:WCWV');
INSERT INTO public.beacon VALUES ('B0b176a4c7617', '2024-10-05 07:46:33.762826+00', '2025-02-15 21:37:44.819172+00', 'U3a33697ffab9', 'Ready for a Riddle Challenge?', 'Hey everyone, quick update from my very eventful adventure (still not sure how I ended up here, but I digress 😅). So, I just met this... interesting fellow. Calls himself Gollum. Bit of a loner, lives in a cave, seems to have some issues, but here’s the fun part: he’s OBSESSED with riddles. Like, seriously, you’d think they were his second breakfast or something.



Long story short, we got into this whole back-and-forth riddle-off thing, and it’s actually kinda fun! Thought I’d invite all of you to join in. 🧐 Want to test your wits against the mysterious Gollum? Think you’ve got a brain sharp enough to handle it? 🧩🤔



I’ll start: “What has roots as nobody sees, Is taller than trees, Up, up it goes, And yet never grows?” 🌲🌄 (A classic, if I do say so myself 😉)



Post your answers below, or throw your own riddles into the mix! Let''s see who can outsmart Gollum... if you dare. 🐟 (Fair warning: he’s weirdly good at this.)



Let the riddles begin! 🎉', '["2024-10-05 00:00:00+00","2025-10-05 00:00:00+00"]', true, true, NULL, NULL, 'There and Back Again', 337, 600, 'q12PJQIA8_.8ozIUx]WA.8IBM{?uM{IA%ga}t6R*azx]MyRj%fRjofozV@WBj[t8j[M{MxkCxuV@WBkCWBofMxtRtRMxkCtRV@oL');
INSERT INTO public.beacon VALUES ('Be8bb41f4353e', '2024-10-05 07:39:48.255085+00', '2025-02-15 21:37:52.461372+00', 'U3a33697ffab9', 'Can someone look at this????', 'Hi, um... so I just signed something and I’m not entirely sure what I’ve gotten myself into (😬). I was enjoying my breakfast this morning, nice and quiet, when a bunch of dwarves and this very persuasive “wizard” showed up at my door. Now, I’m apparently part of a startup or something?? 🤷‍♂️



Anyway, they handed me this contract (pic attached 📸👇), and it mentions dragons, mountains, and “unspecified dangers” (that part is in bold, btw, which seems... worrisome?). They said there’s “treasure” at the end, but also a lot of running, some swords, and... fire?? 🔥😨



I’d like to think I’m more of a stay-at-home-with-tea kind of guy, not the “charge-into-danger-with-13-dwarves” type. But here we are. So, um… any lawyers out there? Maybe someone with experience in... I don’t know, “dragon-related liability”? Asking for a friend (who is me).



Also, is “permanent disfigurement” a normal clause in these things?!?!



Thanks in advance! (Seriously, I could really use some advice.)

', '["2024-10-05 00:00:00+00","2025-10-05 00:00:00+00"]', true, true, 12.400095392984552, -8.085937500000002, 'Community Support', 1066, 600, '-JA]+--o0M0MR*-:t7t6RjNGj[s:Ipt6ofR*oLayxtR*j[s:R*ayayRkfRs:j[j[Iot6ofWXofWBNGWBt7t7WVWBxaRkWBoeayoL');
INSERT INTO public.beacon VALUES ('B6bbf9d5766c3', '2024-10-05 08:02:02.825578+00', '2024-10-05 08:02:02.825578+00', 'U3a33697ffab9', 'Hide and Seek... with a Dragon?', 'Hello again, brave (or slightly crazy) adventurers! Sorry, there will be no pic in this post, as it may compromise my position ;)



😅 So, this next event is... well, let’s just say it’s for those of you who really love a challenge and have a very good hiding spot. Ever wondered what it’s like to play hide and seek with a dragon? No? Well, I didn’t either, but here we are... 😳



Join us for "Hide and Seek with Smaug"—an experience like no other (and hopefully not your last 🤞). The rules are simple: find a spot, stay out of sight, and try not to become a crispy snack. The last one standing wins... bragging rights and possibly survival! 🔥🏆



Why should you join?

 – Test your nerves of steel (or discover they’re made of jelly).

 – Experience the thrill of being hunted by the most infamous dragon in  – Middle-earth. 🐉



It’s a once-in-a-lifetime opportunity (hopefully not literally). 🤷‍♂️



📅 Date: TBD (depends on when Smaug’s feeling playful) 📍 

Location: Lonely Mountain (prime real estate for hide-and-seek enthusiasts, trust me)



How to prepare:

 – Practice being really quiet. Smaug has sharp ears, and his fire-breathing abilities are... well, you know, extensive. 🔥

 – Dress appropriately—flame-resistant clothing highly recommended. 🧥🔥

 – Don’t bring anything shiny. Seriously. He’s got a thing for gold and jewels, and you really don’t want his attention. 💍



Are you up for the challenge? Hide, seek, and... try not to get roasted. 😅



Sign up below, or just show up (preferably with your will in order). Good luck, and may the best hider win!

', NULL, true, false, NULL, NULL, NULL, 0, 0, '');
INSERT INTO public.beacon VALUES ('Bdbd14ea14b6f', '2024-10-05 08:43:18.209028+00', '2024-10-05 08:43:18.209028+00', 'U2becfc64c13b', 'Ready for Adventure', 'Dear friends and aspiring adventurers, I am pleased to announce that the team is officially assembled and prepared to embark on our quest! With a diverse mix of talents and a few unexpected heroes, we’re set to disrupt the status quo and tackle whatever challenges lie ahead.



As always, I’ll be stepping back occasionally to let the team find their footing, but rest assured, I’ll return just in time to sprinkle a bit of magic where it’s most needed. Let the journey begin! 🚀✨

', NULL, true, false, NULL, NULL, 'QuestForGlory', 0, 0, '');
INSERT INTO public.beacon VALUES ('B4268797cc8ee', '2024-10-05 08:14:48.954836+00', '2025-02-15 21:37:47.561732+00', 'U3a33697ffab9', 'Misplaced Silver Spoons!', 'Good people of Hobbiton, friends, neighbors—and a certain Lobelia Sackville-Baggins (yes, I know who you are)!



Let me make something very clear: I am not dead. Alive, well, and very much back at Bag End, thank you very much! 👋 Though I appreciate the... enthusiasm with which some of you leapt at the opportunity to make off with my things during my temporary absence. 😤



Now, after a long journey filled with fire-breathing dragons and far-too-many near-death experiences, I’ve come home to find my belongings auctioned off as though I were nothing more than a distant memory! Most of my dear possessions have been returned (thank you for that, at least). 



But my silver spoons?



Still missing. 😠



Now, I am a reasonable hobbit, but let’s be frank—I know who took them. Don’t think for a second that your sneaky fingers went unnoticed, Lobelia. Yes, you! Those spoons have been in my family for generations, and it’s high time they found their way back to where they belong.



So, consider this your final notice:



1. Return the spoons immediately.

2. No questions asked, but you can leave them anonymously at Bag End’s front gate if you feel too embarrassed to face me. 🏡

3. If they aren’t back in my possession by the end of the week, I will be forced to take more... public measures. (Let’s not make this any more awkward than it already is, shall we?)



I am deeply, deeply upset that a hobbit could stoop so low as to rob another under such circumstances. Especially spoons—my best silver spoons, no less! Have we no decency left in Hobbiton? Has our community become so tarnished by greed?



I expect swift action. And Lobelia—if you’re reading this, know that I will get them back one way or another. The Sackville-Bagginses have gone too far this time. 😡



Regards,

Bilbo Baggins (still very much alive and missing my silverware).

', NULL, true, true, NULL, NULL, NULL, 337, 600, 'qEBy?Jg3~p-;WVM{9FIB9F4oRj9Gt6oz%f%fX8%Lt6bIxtRjWBRkxat8M|%LIVs.RjM{9FxZM{adt7ay%Mt7xut6oLozaeWBV@Rk');
INSERT INTO public.beacon VALUES ('Bec4566ce9bd4', '2024-10-05 08:45:20.221921+00', '2024-10-05 08:45:20.221921+00', 'U2becfc64c13b', 'Behold, Erebor Awaits!', 'At long last, we have caught our first glimpse of Erebor, the Lonely Mountain! Its majestic peaks stand tall against the horizon, a testament to the rich history and treasure that lie within. Our journey has led us to this pivotal moment, and the excitement in the air is palpable.



As we prepare to face the challenges ahead, let us remember the courage that brought us here. Together, we will reclaim what was lost and forge a brighter future. Adventure beckons!', NULL, true, false, NULL, NULL, NULL, 0, 0, '');
INSERT INTO public.beacon VALUES ('B3b1ee4d8fc29', '2024-10-05 08:47:08.105218+00', '2024-10-05 08:47:08.105218+00', 'U2becfc64c13b', 'Renovation of the Angmar Tombs', 'Friends and allies, I am reaching out today to rally support for a worthy cause: the restoration of the ancient tombs of the Kings of Angmar. These sites, steeped in history and magic, deserve our attention and respect.



As guardians of the legacy of our realms, it is our duty to preserve these monuments and honor the stories they hold. Your contributions, no matter how small, will help restore the dignity of these tombs and ensure that the lessons of the past are not forgotten.



Join me in this noble endeavor, and together, we can make a lasting impact!

', NULL, true, false, NULL, NULL, 'Community Support', 0, 0, '');
INSERT INTO public.beacon VALUES ('B89b51dc35863', '2024-10-05 08:47:51.111981+00', '2024-10-05 08:47:51.111981+00', 'U2becfc64c13b', 'Dwarven Enterprises: A Triumph', 'Esteemed friends, I am thrilled to report that our dwarven allies have achieved remarkable success in their latest ventures! Through hard work, innovation, and a dash of that signature dwarven tenacity, they have reclaimed their riches and reestablished their place in the market.



The treasures of Erebor are flowing once more, and their craftsmanship is earning accolades far and wide. This success not only strengthens their legacy but also enriches our entire community. Let us raise our glasses to our steadfast dwarven friends and the bright future that lies ahead!

', NULL, true, false, NULL, NULL, 'QuestForGlory', 0, 0, '');
INSERT INTO public.beacon VALUES ('B2005fe10663d', '2024-10-05 09:21:04.257577+00', '2024-10-05 09:21:04.257577+00', 'Ue479f7b03b5d', 'Free Fish Giveaway', 'Hey, everyone. We''re giving away fresh fish to those in need. Swing by the market square today.', NULL, true, false, NULL, NULL, 'Community Support', 0, 0, '');
INSERT INTO public.beacon VALUES ('B7e7517882a1d', '2024-10-05 09:22:48.555871+00', '2024-10-05 09:22:48.555871+00', 'Ue479f7b03b5d', 'Burgomeister Issues', 'The bourgomeister’s decisions are costing us. We need better leadership, not empty promises. Time for a change. Let’s meet at the tavern tonight to discuss this further.', NULL, true, false, NULL, NULL, NULL, 0, 0, '');
INSERT INTO public.beacon VALUES ('B80372f051f17', '2024-10-05 09:23:02.294578+00', '2024-10-05 09:23:02.294578+00', 'Ue479f7b03b5d', 'Aid for Dragon Victims ', 'We’re collecting donations and supplies for those affected by the recent dragon event. Every bit helps. Bring your contributions to the old mill.', NULL, true, false, NULL, NULL, 'Community Support', 0, 0, '');
INSERT INTO public.beacon VALUES ('Baadac7ab80fe', '2024-10-05 09:48:31.417502+00', '2024-10-05 09:48:31.417502+00', 'U36906cde6568', 'Baggins Loses, We Eats It Whole', '', NULL, true, false, NULL, NULL, NULL, 0, 0, '');
INSERT INTO public.beacon VALUES ('Bcd0a6c69a705', '2024-10-05 08:54:08.351183+00', '2025-02-15 21:37:19.732534+00', 'U4d9267c70eab', 'Protect Our Forests', 'Dear citizens of Middle-earth, it has come to my attention that recent events have left our beloved forests in peril. The reckless antics of certain individuals, including those who claim to be guardians of our realm, have resulted in devastating fires that threaten our natural beauty and the cultural traditions intertwined with it.

As a concerned neighbor and advocate for the preservation of our environment, I urge each of you to join me in raising awareness and funds for the restoration of these precious lands. Together, we can combat the damage done and promote sustainable practices that honor both nature and our shared heritage.

Let us not forget: true guardianship means safeguarding our world for future generations. Remember, not all heroes wear capes—some hold the power of nature in their hands.', NULL, false, true, 6.303006819818279, -10.772096905857326, 'Save the Middle-Earth', 337, 600, 'q67wyp?^3sTx?GtS9[NbrCU^H=DiM{j]X8kWEjkDz:RkJBR*$*r?lTt-%2%MpIX7t7r=IWIUZ~iwWBWBjFs9t8aKWWbFs.t7jZkX');
INSERT INTO public.beacon VALUES ('Bb9d31c168baf', '2024-10-05 09:18:41.778022+00', '2025-02-15 21:39:08.099858+00', 'Ue79d43c03425', 'Uh, Hi Everyone!', 'So, um, I was thinking... we really need to help the hedgehogs in Mirkwood! They’re having a tough time, you know, and, um, they’re kinda adorable, right?

I mean, it’s important for biodiversity and all that! So we’re collecting, uh, donations? And maybe some snacks for our spiky friends? Every little bit helps, really! Let’s, um, make sure they have what they need to thrive!

If you can help, just... uh, reach out! The trees will thank you!', NULL, true, true, 9.138705747534251, -8.934077639132738, 'Save the Middle-Earth', 600, 600, ':25EpV5u^k?GNf^hNJ-nkY%MtRRojGxZoJR-0Mw[0gM|RQ9bxYNHD%ROIUE2WBNGa{V[s%-O$|Iq-nbbj[xD~9bH-o-okD-nW=xZxaR.ofs:I=%KR.ogE5R-9cV@M|M}s.S5');
INSERT INTO public.beacon VALUES ('B080a0d5de22d', '2024-10-05 09:12:13.14771+00', '2025-02-15 21:36:59.968806+00', 'U41906748a800', 'Damn Those Unruly Pests!', 'HEAR ME, MERE MORTALS AND ASPIRING CHAMPIONS! I, SMAUG THE MAGNIFICENT, RULER OF THE SKIES AND GUARDIAN OF UNTOLD TREASURES, AM BESET BY A MOST INSUFFERABLE MENACE! A WRETCHED THRUSH DARES TO PECK INCESSANTLY AT MY BRAIN, DISRUPTING MY MAGNIFICENT THOUGHTS OF WEALTH AND CONQUEST!



AND AS IF THAT WEREN’T ENOUGH, THERE ARE RUMORS OF DWARVEN RODENTS ATTEMPTING TO USURP MY DOMAIN! I DEMAND ASSISTANCE FROM THE BRAVEST AMONG YOU! ONLY THOSE WORTHY OF MY PRESENCE MAY APPROACH; THE FEEBLE WILL BE SCORCHED BY THE VERY FLAMES OF MY FURY!



JOIN ME IN VANQUISHING THESE PESTS, FOR THEY THREATEN NOT JUST MY PEACE, BUT THE VERY BALANCE OF THE REALM. TOGETHER, WE SHALL FORGE A PATH TO DOMINANCE OVER ALL THAT IS PESTILENT AND UNWANTED!

', NULL, true, true, NULL, NULL, 'SMAUG SPEAKS', 337, 600, 'q35Xf6~8xVI:oJ%1xZNb5U9w9vIpWCxZs:WC^N=^$$n%s.ofkBbGEOEOIqNHR+WCjtayxD$$xYxZoeoLayjsI;I;WXs:s.WVNHR+');
INSERT INTO public.beacon VALUES ('B20f3d51e498f', '2024-10-05 09:06:32.734284+00', '2025-02-15 21:37:05.89948+00', 'U4d9267c70eab', 'Protect Our Forests', 'Dear citizens of Middle-earth, it has come to my attention that recent events have left our beloved forests in peril. The reckless antics of certain individuals, including those who claim to be guardians of our realm, have resulted in devastating fires that threaten our natural beauty and the cultural traditions intertwined with it.

As a concerned neighbor and advocate for the preservation of our environment, I urge each of you to join me in raising awareness and funds for the restoration of these precious lands. Together, we can combat the damage done and promote sustainable practices that honor both nature and our shared heritage.

Let us not forget: true guardianship means safeguarding our world for future generations. Remember, not all heroes wear capes—some hold the power of nature in their hands.

', NULL, true, true, NULL, NULL, 'Save the Middle-Earth', 337, 600, 'q67wyp?^3sTx?GtS9[NbrCU^H=DiM{j]X8kWEjkDz:RkJBR*$*r?lTt-%2%MpIX7t7r=IWIUZ~iwWBWBjFs9t8aKWWbFs.t7jZkX');
INSERT INTO public.beacon VALUES ('Baf813d1b4acf', '2024-10-05 18:10:27.637655+00', '2025-02-15 21:37:11.947162+00', 'U4d9267c70eab', 'Boris the Cat', '', NULL, true, true, NULL, NULL, NULL, 383, 600, 'qPGl3V0JIS%iE2NFR.xu%i$~ROx_ogNGR*f,afxaxux^R*R.Rjf,%gVs%NWUWXbcRkWB%M%MIoW-R,WCt8R*xufSWBofWBozWAkC');
INSERT INTO public.beacon VALUES ('B3c8ee2c064f6', '2024-10-05 07:53:40.786286+00', '2025-02-15 21:37:49.222203+00', 'U3a33697ffab9', 'Support the Journey, Rent a Pony', 'Hello again, fellow adventurers (and everyone who prefers the comfort of their homes—trust me, I understand you 🫖😌). So, as you know, long journeys can be tiring—especially when you’re being chased by all sorts of unpleasant creatures. And while I’ve learned to appreciate walking (sort of?), nothing beats traveling in style... on a pony! 🐎🎒



We’ve partnered with Beorn’s Pony Service to make your travels so much easier. Rent a pony, and 100% of the proceeds will go to Beorn’s wilderness fund to protect local wildlife and... well, the man himself (he’s very generous but could use some help with the upkeep of his lands 🏞️). Plus, your donation means we get to keep these adorable ponies fed and happy! 🐴❤️



💡 Why ponies?

Ponies are great company! (Silent, unlike certain wizards.)

They carry all your things. (Trust me, there’s always more than you expect.)

And... they make running from trolls, wolves, or just being late for second breakfast a lot easier! 🍳🥐



🎯 How can you help?

Rent a pony for your next journey, or

Donate directly to Beorn''s cause—let’s keep his lands safe and free of goblins (and maybe cut down on the number of “unfriendly visitors” 🐻👀).



Every bit helps! If you’ve ever relied on a sturdy pony, now’s your chance to give back.

', NULL, true, true, 13.564832686963012, 1.828129291534424, NULL, 337, 600, 'qCCZa.Di9u%yIpbHk8.6*JDisT.7smxaV@XSS+R5M}XAxZt6aMR.NMR%kCt8bEjZozt6N@%1%1SfIVRktQocRjxat7WAaLR*kCe:');


--
-- Data for Name: beacon_pinned; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.beacon_pinned VALUES ('U8c85f8c3bef7', 'B20f3d51e498f');
INSERT INTO public.beacon_pinned VALUES ('U8c85f8c3bef7', 'B0055751ce4cc');


--
-- Data for Name: comment; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.comment VALUES ('C9b36f904697e', 'U286f94380611', 'Far over the Misty Mountains cold', '2024-10-03 07:59:12.25331+00', 'Bc1cb783b0159');
INSERT INTO public.comment VALUES ('C8bf3d2545b6b', 'U7aa6bd888278', 'To dungeons deep and caverns old', '2024-10-03 08:02:43.666854+00', 'B0055751ce4cc');
INSERT INTO public.comment VALUES ('C757806312ae1', 'U7aa6bd888278', 'To dungeons deep and caverns old', '2024-10-03 08:04:05.661421+00', 'Bc1cb783b0159');
INSERT INTO public.comment VALUES ('C359515064aae', 'U050e67479957', 'We must away, ere break of day', '2024-10-05 10:22:04.391275+00', 'Bc1cb783b0159');
INSERT INTO public.comment VALUES ('C98d9978b7d6c', 'U6301c73d1354', 'To seek our pale enchanted gold', '2024-10-05 10:22:26.880439+00', 'Bc1cb783b0159');
INSERT INTO public.comment VALUES ('C3fe79b19de5a', 'Ub0100d7bad5f', 'Mmm-hmm-hmm-hmm', '2024-10-05 10:22:58.444086+00', 'Bc1cb783b0159');
INSERT INTO public.comment VALUES ('C1b28e93382e1', 'U8ebde6fbfd3f', 'Sorry, cousin, my boar is allergic to dragons. Wish you all the luck though!', '2024-10-05 10:23:28.247599+00', 'Bc1cb783b0159');
INSERT INTO public.comment VALUES ('C7e507d2dd112', 'U15f925d86858', 'Wath if Smaug is already dead? What if the dragon has been slain by some other creature? He might not even be there!

', '2024-10-05 10:23:51.895303+00', 'Bc1cb783b0159');
INSERT INTO public.comment VALUES ('C842a34fddec2', 'U8ebde6fbfd3f', 'Not convinced', '2024-10-05 10:24:24.202416+00', 'Bc1cb783b0159');
INSERT INTO public.comment VALUES ('C25efb4fe632b', 'Udab52ec61933', 'So, there will still be only 13 of us? 

', '2024-10-05 10:25:16.336249+00', 'Bc1cb783b0159');
INSERT INTO public.comment VALUES ('C9b1d2b73215c', 'U2becfc64c13b', '14. I''ve got us a burglar.

', '2024-10-05 10:25:54.705782+00', 'Bc1cb783b0159');
INSERT INTO public.comment VALUES ('C47a273145740', 'U3a33697ffab9', '!!! … … Good morning!!', '2024-10-05 10:26:22.601529+00', 'Bc1cb783b0159');


--
-- Data for Name: message; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: user_context; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.user_context VALUES ('U286f94380611', 'QuestForGlory');
INSERT INTO public.user_context VALUES ('U7aa6bd888278', 'QuestForGlory');
INSERT INTO public.user_context VALUES ('U3a33697ffab9', 'Community Support');
INSERT INTO public.user_context VALUES ('U3a33697ffab9', 'There and Back Again');
INSERT INTO public.user_context VALUES ('U2becfc64c13b', 'QuestForGlory');
INSERT INTO public.user_context VALUES ('U2becfc64c13b', 'Community Support');
INSERT INTO public.user_context VALUES ('U4d9267c70eab', 'Save the Middle-Earth');
INSERT INTO public.user_context VALUES ('U41906748a800', 'SMAUG SPEAKS');
INSERT INTO public.user_context VALUES ('Ue79d43c03425', 'Save the Middle-Earth');
INSERT INTO public.user_context VALUES ('Ue479f7b03b5d', 'Community Support');


--
-- Data for Name: user_updates; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: vote_beacon; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.vote_beacon VALUES ('U7aa6bd888278', 'B0055751ce4cc', 1, '2024-10-03 08:03:38.941036+00', '2024-10-03 08:03:38.941036+00');
INSERT INTO public.vote_beacon VALUES ('U7aa6bd888278', 'B521ff7422d52', 1, '2024-10-03 08:03:41.10328+00', '2024-10-03 08:03:41.10328+00');
INSERT INTO public.vote_beacon VALUES ('U41906748a800', 'B0055751ce4cc', -5, '2024-12-09 15:58:12.543312+00', '2024-12-09 15:58:14.871926+00');
INSERT INTO public.vote_beacon VALUES ('U7aa6bd888278', 'Bc1cb783b0159', 4, '2024-10-03 08:03:42.829423+00', '2024-10-04 14:50:21.708328+00');
INSERT INTO public.vote_beacon VALUES ('U050e67479957', 'Bc1cb783b0159', 1, '2024-10-05 10:21:34.536189+00', '2024-10-05 10:21:34.536189+00');
INSERT INTO public.vote_beacon VALUES ('U6301c73d1354', 'Bc1cb783b0159', 1, '2024-10-05 10:22:35.161263+00', '2024-10-05 10:22:35.161263+00');
INSERT INTO public.vote_beacon VALUES ('Ub0100d7bad5f', 'Bc1cb783b0159', 1, '2024-10-05 10:23:06.020763+00', '2024-10-05 10:23:06.020763+00');
INSERT INTO public.vote_beacon VALUES ('U8ebde6fbfd3f', 'Bc1cb783b0159', 1, '2024-10-05 10:23:31.888146+00', '2024-10-05 10:23:31.888146+00');
INSERT INTO public.vote_beacon VALUES ('U15f925d86858', 'Bc1cb783b0159', 1, '2024-10-05 10:23:42.455178+00', '2024-10-05 10:23:42.455178+00');
INSERT INTO public.vote_beacon VALUES ('Udab52ec61933', 'Bc1cb783b0159', 1, '2024-10-05 10:25:09.588901+00', '2024-10-05 10:25:09.588901+00');
INSERT INTO public.vote_beacon VALUES ('U2becfc64c13b', 'Bc1cb783b0159', 1, '2024-10-05 10:25:48.548917+00', '2024-10-05 10:25:48.548917+00');
INSERT INTO public.vote_beacon VALUES ('U286f94380611', 'B0b176a4c7617', -2, '2024-12-09 16:03:55.834734+00', '2024-12-09 16:03:56.609374+00');
INSERT INTO public.vote_beacon VALUES ('U286f94380611', 'B080a0d5de22d', -4, '2024-12-09 16:03:08.090386+00', '2024-12-09 16:03:09.804406+00');
INSERT INTO public.vote_beacon VALUES ('U41906748a800', 'B3b1ee4d8fc29', -2, '2024-12-09 15:59:24.706719+00', '2024-12-09 15:59:25.265224+00');
INSERT INTO public.vote_beacon VALUES ('U41906748a800', 'B0b176a4c7617', -1, '2024-12-09 15:59:26.801211+00', '2024-12-09 15:59:26.801211+00');
INSERT INTO public.vote_beacon VALUES ('U41906748a800', 'B521ff7422d52', -5, '2024-12-09 15:58:19.201649+00', '2024-12-09 15:58:21.489498+00');
INSERT INTO public.vote_beacon VALUES ('U41906748a800', 'B4268797cc8ee', -2, '2024-12-09 15:59:28.511974+00', '2024-12-09 15:59:29.26752+00');
INSERT INTO public.vote_beacon VALUES ('U8c85f8c3bef7', 'Bc1cb783b0159', 1, '2024-11-13 10:25:51.30877+00', '2024-11-13 10:25:51.30877+00');
INSERT INTO public.vote_beacon VALUES ('U8c85f8c3bef7', 'B080a0d5de22d', 1, '2024-11-13 10:25:53.554387+00', '2024-11-13 10:25:53.554387+00');
INSERT INTO public.vote_beacon VALUES ('U41906748a800', 'Baadac7ab80fe', 2, '2024-12-09 15:59:33.440425+00', '2024-12-09 15:59:35.099191+00');
INSERT INTO public.vote_beacon VALUES ('U41906748a800', 'B20f3d51e498f', 5, '2024-12-09 15:58:24.688739+00', '2024-12-09 15:58:30.163329+00');
INSERT INTO public.vote_beacon VALUES ('U286f94380611', 'B6d130d7414d1', 3, '2024-12-09 16:03:34.523912+00', '2024-12-09 16:03:42.146524+00');
INSERT INTO public.vote_beacon VALUES ('U286f94380611', 'B6bbf9d5766c3', 5, '2024-12-09 16:03:32.546578+00', '2024-12-09 16:03:33.854478+00');
INSERT INTO public.vote_beacon VALUES ('U4d9267c70eab', 'Bc1cb783b0159', -5, '2024-12-09 16:00:02.30749+00', '2024-12-09 16:00:04.220223+00');
INSERT INTO public.vote_beacon VALUES ('U4d9267c70eab', 'B86a6e5de190a', -4, '2024-12-09 16:01:08.511019+00', '2024-12-09 16:01:10.097195+00');
INSERT INTO public.vote_beacon VALUES ('U286f94380611', 'B20f3d51e498f', -5, '2024-12-09 16:03:10.91916+00', '2024-12-09 16:03:12.466155+00');
INSERT INTO public.vote_beacon VALUES ('U4d9267c70eab', 'B6bbf9d5766c3', -5, '2024-12-09 16:00:39.809657+00', '2024-12-09 16:00:41.6712+00');
INSERT INTO public.vote_beacon VALUES ('U41906748a800', 'Bc1cb783b0159', -5, '2024-12-09 15:57:48.070992+00', '2024-12-09 15:57:51.122003+00');
INSERT INTO public.vote_beacon VALUES ('U41906748a800', 'B6bbf9d5766c3', -5, '2024-12-09 15:58:53.061127+00', '2024-12-09 15:58:56.483272+00');
INSERT INTO public.vote_beacon VALUES ('U4d9267c70eab', 'B080a0d5de22d', 5, '2024-12-09 16:00:13.624397+00', '2024-12-09 16:00:15.995016+00');
INSERT INTO public.vote_beacon VALUES ('U4d9267c70eab', 'Baadac7ab80fe', 3, '2024-12-09 16:01:11.685061+00', '2024-12-09 16:01:13.062342+00');
INSERT INTO public.vote_beacon VALUES ('U41906748a800', 'B3c8ee2c064f6', -6, '2024-12-09 15:58:59.604688+00', '2024-12-09 15:59:00.701794+00');
INSERT INTO public.vote_beacon VALUES ('U41906748a800', 'B988f628fa22f', -5, '2024-12-09 15:57:56.594764+00', '2024-12-09 15:57:58.199986+00');
INSERT INTO public.vote_beacon VALUES ('U41906748a800', 'Baf813d1b4acf', 7, '2024-12-09 15:58:37.232599+00', '2024-12-09 15:59:02.695765+00');
INSERT INTO public.vote_beacon VALUES ('U41906748a800', 'B6d130d7414d1', -5, '2024-12-09 15:57:59.127907+00', '2024-12-09 15:58:00.690281+00');
INSERT INTO public.vote_beacon VALUES ('U286f94380611', 'B4342c0e949fb', 2, '2024-12-09 16:03:36.774915+00', '2024-12-09 16:03:42.861884+00');
INSERT INTO public.vote_beacon VALUES ('U4d9267c70eab', 'B3c8ee2c064f6', -3, '2024-12-09 16:00:43.607021+00', '2024-12-09 16:00:44.622123+00');
INSERT INTO public.vote_beacon VALUES ('U4d9267c70eab', 'B0055751ce4cc', -3, '2024-12-09 16:00:27.621878+00', '2024-12-09 16:00:28.751108+00');
INSERT INTO public.vote_beacon VALUES ('U41906748a800', 'B4342c0e949fb', -5, '2024-12-09 15:58:01.831394+00', '2024-12-09 15:58:05.080164+00');
INSERT INTO public.vote_beacon VALUES ('U4d9267c70eab', 'B3b1ee4d8fc29', -4, '2024-12-09 16:01:14.801838+00', '2024-12-09 16:01:15.692436+00');
INSERT INTO public.vote_beacon VALUES ('U4d9267c70eab', 'B80372f051f17', -2, '2024-12-09 16:00:47.105666+00', '2024-12-09 16:00:47.729258+00');
INSERT INTO public.vote_beacon VALUES ('U41906748a800', 'B86a6e5de190a', -2, '2024-12-09 15:59:12.478595+00', '2024-12-09 15:59:16.173496+00');
INSERT INTO public.vote_beacon VALUES ('U286f94380611', 'B3b1ee4d8fc29', 2, '2024-12-09 16:03:57.389242+00', '2024-12-09 16:03:57.903081+00');
INSERT INTO public.vote_beacon VALUES ('U41906748a800', 'Be8bb41f4353e', -2, '2024-12-09 15:59:18.146401+00', '2024-12-09 15:59:18.934946+00');
INSERT INTO public.vote_beacon VALUES ('U41906748a800', 'Bb4dbbb63b373', -1, '2024-12-09 15:59:21.129723+00', '2024-12-09 15:59:21.695152+00');
INSERT INTO public.vote_beacon VALUES ('U4d9267c70eab', 'B4268797cc8ee', -3, '2024-12-09 16:01:17.85777+00', '2024-12-09 16:01:20.101933+00');
INSERT INTO public.vote_beacon VALUES ('U4d9267c70eab', 'B0b176a4c7617', -3, '2024-12-09 16:00:52.008791+00', '2024-12-09 16:00:53.820688+00');
INSERT INTO public.vote_beacon VALUES ('U4d9267c70eab', 'B521ff7422d52', -6, '2024-12-09 16:00:30.539492+00', '2024-12-09 16:00:35.050898+00');
INSERT INTO public.vote_beacon VALUES ('U286f94380611', 'Be8bb41f4353e', 4, '2024-12-09 16:03:45.158121+00', '2024-12-09 16:03:46.320513+00');
INSERT INTO public.vote_beacon VALUES ('U4d9267c70eab', 'Bdbd14ea14b6f', -1, '2024-12-09 16:01:21.335888+00', '2024-12-09 16:01:21.850009+00');
INSERT INTO public.vote_beacon VALUES ('U4d9267c70eab', 'Be8bb41f4353e', -5, '2024-12-09 16:00:58.505588+00', '2024-12-09 16:01:00.243214+00');
INSERT INTO public.vote_beacon VALUES ('U286f94380611', 'B3c8ee2c064f6', 5, '2024-12-09 16:03:17.822131+00', '2024-12-09 16:03:19.530393+00');
INSERT INTO public.vote_beacon VALUES ('U286f94380611', 'B988f628fa22f', 1, '2024-12-09 16:03:27.473759+00', '2024-12-09 16:03:27.473759+00');
INSERT INTO public.vote_beacon VALUES ('U4d9267c70eab', 'Bb4dbbb63b373', -5, '2024-12-09 16:01:04.506198+00', '2024-12-09 16:01:06.876698+00');
INSERT INTO public.vote_beacon VALUES ('U286f94380611', 'B89b51dc35863', 3, '2024-12-09 16:04:06.028105+00', '2024-12-09 16:04:06.867325+00');
INSERT INTO public.vote_beacon VALUES ('U286f94380611', 'B2005fe10663d', -3, '2024-12-09 16:04:01.408607+00', '2024-12-09 16:04:02.227114+00');
INSERT INTO public.vote_beacon VALUES ('U286f94380611', 'Bb4dbbb63b373', 4, '2024-12-09 16:03:47.521783+00', '2024-12-09 16:03:49.308589+00');
INSERT INTO public.vote_beacon VALUES ('U286f94380611', 'Baf813d1b4acf', -5, '2024-12-09 16:03:28.36433+00', '2024-12-09 16:03:30.759416+00');
INSERT INTO public.vote_beacon VALUES ('U286f94380611', 'Bec4566ce9bd4', 3, '2024-12-09 16:04:14.608953+00', '2024-12-09 16:04:15.352519+00');
INSERT INTO public.vote_beacon VALUES ('U286f94380611', 'B4268797cc8ee', 4, '2024-12-09 16:04:08.421476+00', '2024-12-09 16:04:09.582413+00');
INSERT INTO public.vote_beacon VALUES ('U286f94380611', 'B86a6e5de190a', 4, '2024-12-09 16:03:52.783625+00', '2024-12-09 16:03:53.898251+00');
INSERT INTO public.vote_beacon VALUES ('U286f94380611', 'B80372f051f17', -3, '2024-12-09 16:03:59.699394+00', '2024-12-09 16:04:04.521285+00');
INSERT INTO public.vote_beacon VALUES ('U3a33697ffab9', 'B080a0d5de22d', -3, '2024-12-09 16:04:43.401132+00', '2024-12-09 16:04:44.556603+00');
INSERT INTO public.vote_beacon VALUES ('U286f94380611', 'Bdbd14ea14b6f', 3, '2024-12-09 16:04:10.957791+00', '2024-12-09 16:04:11.765244+00');
INSERT INTO public.vote_beacon VALUES ('U3a33697ffab9', 'B89b51dc35863', 4, '2024-12-09 16:04:48.565048+00', '2024-12-09 16:04:49.714483+00');
INSERT INTO public.vote_beacon VALUES ('U286f94380611', 'B0cb05535835f', 3, '2024-12-09 16:04:12.69392+00', '2024-12-09 16:04:13.414837+00');
INSERT INTO public.vote_beacon VALUES ('U3a33697ffab9', 'B20f3d51e498f', -4, '2024-12-09 16:04:40.086799+00', '2024-12-09 16:04:41.009437+00');
INSERT INTO public.vote_beacon VALUES ('U286f94380611', 'B7e7517882a1d', -3, '2024-12-09 16:04:17.748566+00', '2024-12-09 16:04:19.57219+00');
INSERT INTO public.vote_beacon VALUES ('U3a33697ffab9', 'Bc1cb783b0159', 5, '2024-10-05 10:26:11.528163+00', '2024-12-09 16:04:38.797899+00');
INSERT INTO public.vote_beacon VALUES ('U3a33697ffab9', 'B0cb05535835f', 5, '2024-12-09 16:04:45.990782+00', '2024-12-09 16:04:47.573011+00');
INSERT INTO public.vote_beacon VALUES ('U3a33697ffab9', 'Bdbd14ea14b6f', 4, '2024-12-09 16:04:50.911075+00', '2024-12-09 16:04:51.95672+00');
INSERT INTO public.vote_beacon VALUES ('U3a33697ffab9', 'B3b1ee4d8fc29', 3, '2024-12-09 16:04:53.749721+00', '2024-12-09 16:04:54.539346+00');
INSERT INTO public.vote_beacon VALUES ('U3a33697ffab9', 'Bec4566ce9bd4', 4, '2024-12-09 16:05:08.246593+00', '2024-12-09 16:05:09.52876+00');
INSERT INTO public.vote_beacon VALUES ('U3a33697ffab9', 'B521ff7422d52', 3, '2024-12-09 16:05:02.353225+00', '2024-12-09 16:05:03.118388+00');
INSERT INTO public.vote_beacon VALUES ('U3a33697ffab9', 'B0055751ce4cc', 4, '2024-12-09 16:05:04.912482+00', '2024-12-09 16:05:06.610154+00');
INSERT INTO public.vote_beacon VALUES ('U3a33697ffab9', 'B6d130d7414d1', 10, '2024-12-09 16:05:10.138936+00', '2024-12-09 16:05:13.917214+00');
INSERT INTO public.vote_beacon VALUES ('U3a33697ffab9', 'B4342c0e949fb', 2, '2024-12-09 16:05:19.539003+00', '2024-12-09 16:05:27.914072+00');
INSERT INTO public.vote_beacon VALUES ('U3a33697ffab9', 'Baf813d1b4acf', -2, '2024-12-09 16:05:15.553478+00', '2024-12-09 16:05:26.416643+00');
INSERT INTO public.vote_beacon VALUES ('U3a33697ffab9', 'B988f628fa22f', 3, '2024-12-09 16:05:28.706239+00', '2024-12-09 16:05:29.304992+00');
INSERT INTO public.vote_beacon VALUES ('U3a33697ffab9', 'Baadac7ab80fe', -3, '2024-12-09 16:05:31.002871+00', '2024-12-09 16:05:32.133493+00');
INSERT INTO public.vote_beacon VALUES ('U3a33697ffab9', 'B80372f051f17', 2, '2024-12-09 16:05:33.165913+00', '2024-12-09 16:05:33.814353+00');
INSERT INTO public.vote_beacon VALUES ('U3a33697ffab9', 'B2005fe10663d', 4, '2024-12-09 16:05:35.128349+00', '2024-12-09 16:05:37.146052+00');
INSERT INTO public.vote_beacon VALUES ('U3a33697ffab9', 'B7e7517882a1d', 3, '2024-12-09 16:05:38.012974+00', '2024-12-09 16:05:39.301455+00');
INSERT INTO public.vote_beacon VALUES ('U3a33697ffab9', 'Bb9d31c168baf', 5, '2024-12-09 16:05:41.099568+00', '2024-12-09 16:05:43.370424+00');


--
-- Data for Name: vote_comment; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.vote_comment VALUES ('U7aa6bd888278', 'C9b36f904697e', 1, '2024-10-03 08:07:08.669744+00', '2024-10-03 08:07:08.669744+00');
INSERT INTO public.vote_comment VALUES ('U286f94380611', 'C757806312ae1', 1, '2024-10-03 08:10:23.226673+00', '2024-10-03 08:10:23.226673+00');
INSERT INTO public.vote_comment VALUES ('U050e67479957', 'C757806312ae1', 1, '2024-10-05 10:22:05.485023+00', '2024-10-05 10:22:05.485023+00');
INSERT INTO public.vote_comment VALUES ('U050e67479957', 'C9b36f904697e', 1, '2024-10-05 10:22:06.219384+00', '2024-10-05 10:22:06.219384+00');
INSERT INTO public.vote_comment VALUES ('U6301c73d1354', 'C9b36f904697e', 1, '2024-10-05 10:22:28.714712+00', '2024-10-05 10:22:28.714712+00');
INSERT INTO public.vote_comment VALUES ('U6301c73d1354', 'C757806312ae1', 1, '2024-10-05 10:22:29.738694+00', '2024-10-05 10:22:29.738694+00');
INSERT INTO public.vote_comment VALUES ('U6301c73d1354', 'C359515064aae', 1, '2024-10-05 10:22:31.169768+00', '2024-10-05 10:22:31.169768+00');
INSERT INTO public.vote_comment VALUES ('Ub0100d7bad5f', 'C98d9978b7d6c', 1, '2024-10-05 10:23:01.192459+00', '2024-10-05 10:23:01.192459+00');
INSERT INTO public.vote_comment VALUES ('Ub0100d7bad5f', 'C359515064aae', 1, '2024-10-05 10:23:01.982947+00', '2024-10-05 10:23:01.982947+00');
INSERT INTO public.vote_comment VALUES ('Ub0100d7bad5f', 'C757806312ae1', 1, '2024-10-05 10:23:02.55198+00', '2024-10-05 10:23:02.55198+00');
INSERT INTO public.vote_comment VALUES ('Ub0100d7bad5f', 'C9b36f904697e', 1, '2024-10-05 10:23:03.16834+00', '2024-10-05 10:23:03.16834+00');
INSERT INTO public.vote_comment VALUES ('U15f925d86858', 'C98d9978b7d6c', 1, '2024-10-05 10:23:54.321849+00', '2024-10-05 10:23:54.321849+00');
INSERT INTO public.vote_comment VALUES ('U15f925d86858', 'C3fe79b19de5a', 1, '2024-10-05 10:23:54.990903+00', '2024-10-05 10:23:54.990903+00');
INSERT INTO public.vote_comment VALUES ('U15f925d86858', 'C1b28e93382e1', 1, '2024-10-05 10:23:55.523317+00', '2024-10-05 10:23:55.523317+00');
INSERT INTO public.vote_comment VALUES ('U15f925d86858', 'C359515064aae', 1, '2024-10-05 10:23:58.036102+00', '2024-10-05 10:23:58.036102+00');
INSERT INTO public.vote_comment VALUES ('U15f925d86858', 'C757806312ae1', 1, '2024-10-05 10:23:58.688504+00', '2024-10-05 10:23:58.688504+00');
INSERT INTO public.vote_comment VALUES ('U15f925d86858', 'C9b36f904697e', 1, '2024-10-05 10:23:59.125058+00', '2024-10-05 10:23:59.125058+00');
INSERT INTO public.vote_comment VALUES ('Udab52ec61933', 'C7e507d2dd112', 1, '2024-10-05 10:25:18.86231+00', '2024-10-05 10:25:18.86231+00');
INSERT INTO public.vote_comment VALUES ('Udab52ec61933', 'C842a34fddec2', -1, '2024-10-05 10:25:19.38472+00', '2024-10-05 10:25:26.3251+00');
INSERT INTO public.vote_comment VALUES ('Udab52ec61933', 'C1b28e93382e1', -1, '2024-10-05 10:25:18.155722+00', '2024-10-05 10:25:31.040427+00');
INSERT INTO public.vote_comment VALUES ('Udab52ec61933', 'C3fe79b19de5a', 1, '2024-10-05 10:25:32.237685+00', '2024-10-05 10:25:32.237685+00');
INSERT INTO public.vote_comment VALUES ('Udab52ec61933', 'C98d9978b7d6c', 1, '2024-10-05 10:25:32.677945+00', '2024-10-05 10:25:32.677945+00');
INSERT INTO public.vote_comment VALUES ('Udab52ec61933', 'C359515064aae', 1, '2024-10-05 10:25:33.423124+00', '2024-10-05 10:25:33.423124+00');
INSERT INTO public.vote_comment VALUES ('Udab52ec61933', 'C757806312ae1', 1, '2024-10-05 10:25:33.887267+00', '2024-10-05 10:25:33.887267+00');
INSERT INTO public.vote_comment VALUES ('Udab52ec61933', 'C9b36f904697e', 1, '2024-10-05 10:25:34.500026+00', '2024-10-05 10:25:34.500026+00');


--
-- Data for Name: vote_opinion; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: vote_user; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.vote_user VALUES ('U4d9267c70eab', 'U3ffe5ced51de', 1, '2024-10-05 10:03:49.787426+00', '2024-10-05 10:03:49.787426+00');
INSERT INTO public.vote_user VALUES ('Ue479f7b03b5d', 'U286f94380611', 1, '2024-10-05 10:04:14.277036+00', '2024-10-05 10:04:14.277036+00');
INSERT INTO public.vote_user VALUES ('Ue479f7b03b5d', 'U41906748a800', 1, '2024-10-05 10:04:23.091402+00', '2024-10-05 10:04:23.091402+00');
INSERT INTO public.vote_user VALUES ('Ue479f7b03b5d', 'U3ffe5ced51de', 1, '2024-10-05 10:04:35.707369+00', '2024-10-05 10:04:35.707369+00');
INSERT INTO public.vote_user VALUES ('U41906748a800', 'U8c85f8c3bef7', 1, '2024-10-05 10:05:01.704425+00', '2024-10-05 10:05:01.704425+00');
INSERT INTO public.vote_user VALUES ('U41906748a800', 'Ue479f7b03b5d', 1, '2024-10-05 10:05:20.096788+00', '2024-10-05 10:05:20.096788+00');
INSERT INTO public.vote_user VALUES ('Ue79d43c03425', 'U2becfc64c13b', 1, '2024-10-05 10:06:20.956478+00', '2024-10-05 10:06:20.956478+00');
INSERT INTO public.vote_user VALUES ('Ue79d43c03425', 'U4d9267c70eab', 1, '2024-10-05 10:06:27.548851+00', '2024-10-05 10:06:27.548851+00');
INSERT INTO public.vote_user VALUES ('Ue79d43c03425', 'Ud14e4cfed365', 1, '2024-10-05 10:06:40.983402+00', '2024-10-05 10:06:40.983402+00');
INSERT INTO public.vote_user VALUES ('Ue79d43c03425', 'Ub13c4a82ab30', 1, '2024-10-05 10:07:00.724882+00', '2024-10-05 10:07:00.724882+00');
INSERT INTO public.vote_user VALUES ('Ue79d43c03425', 'U3ffe5ced51de', 1, '2024-10-05 10:07:16.150282+00', '2024-10-05 10:07:16.150282+00');
INSERT INTO public.vote_user VALUES ('Ub0100d7bad5f', 'U3a33697ffab9', 1, '2024-10-05 10:07:37.755101+00', '2024-10-05 10:07:37.755101+00');
INSERT INTO public.vote_user VALUES ('Ub0100d7bad5f', 'U286f94380611', 1, '2024-10-05 10:07:45.386301+00', '2024-10-05 10:07:45.386301+00');
INSERT INTO public.vote_user VALUES ('Ub0100d7bad5f', 'U7aa6bd888278', 1, '2024-10-05 10:07:54.518442+00', '2024-10-05 10:07:54.518442+00');
INSERT INTO public.vote_user VALUES ('Ub0100d7bad5f', 'U050e67479957', 1, '2024-10-05 10:08:16.990962+00', '2024-10-05 10:08:16.990962+00');
INSERT INTO public.vote_user VALUES ('Ub0100d7bad5f', 'U6301c73d1354', 1, '2024-10-05 10:08:22.394006+00', '2024-10-05 10:08:22.394006+00');
INSERT INTO public.vote_user VALUES ('Ub0100d7bad5f', 'U8ebde6fbfd3f', 1, '2024-10-05 10:08:31.858007+00', '2024-10-05 10:08:31.858007+00');
INSERT INTO public.vote_user VALUES ('Ub0100d7bad5f', 'U2becfc64c13b', 1, '2024-10-05 10:08:38.53909+00', '2024-10-05 10:08:38.53909+00');
INSERT INTO public.vote_user VALUES ('U28846d74623d', 'U2becfc64c13b', 1, '2024-10-05 10:08:55.18421+00', '2024-10-05 10:08:55.18421+00');
INSERT INTO public.vote_user VALUES ('U28846d74623d', 'U286f94380611', 1, '2024-10-05 10:09:01.952654+00', '2024-10-05 10:09:01.952654+00');
INSERT INTO public.vote_user VALUES ('U28846d74623d', 'Udab52ec61933', 1, '2024-10-05 10:09:14.297951+00', '2024-10-05 10:09:14.297951+00');
INSERT INTO public.vote_user VALUES ('Udab52ec61933', 'U28846d74623d', 1, '2024-10-05 10:09:28.508225+00', '2024-10-05 10:09:28.508225+00');
INSERT INTO public.vote_user VALUES ('Udab52ec61933', 'U286f94380611', 1, '2024-10-05 10:09:34.990915+00', '2024-10-05 10:09:34.990915+00');
INSERT INTO public.vote_user VALUES ('Udab52ec61933', 'U2becfc64c13b', 1, '2024-10-05 10:09:41.673236+00', '2024-10-05 10:09:41.673236+00');
INSERT INTO public.vote_user VALUES ('Uffbd6f094f6a', 'U15f925d86858', 1, '2024-10-05 10:09:58.682709+00', '2024-10-05 10:09:58.682709+00');
INSERT INTO public.vote_user VALUES ('Uffbd6f094f6a', 'U2d94f2dd547e', 1, '2024-10-05 10:10:04.751264+00', '2024-10-05 10:10:04.751264+00');
INSERT INTO public.vote_user VALUES ('Uffbd6f094f6a', 'U286f94380611', 1, '2024-10-05 10:10:18.424031+00', '2024-10-05 10:10:18.424031+00');
INSERT INTO public.vote_user VALUES ('Uffbd6f094f6a', 'U2becfc64c13b', 1, '2024-10-05 10:10:24.107835+00', '2024-10-05 10:10:24.107835+00');
INSERT INTO public.vote_user VALUES ('U15f925d86858', 'Uffbd6f094f6a', 1, '2024-10-05 10:10:45.365148+00', '2024-10-05 10:10:45.365148+00');
INSERT INTO public.vote_user VALUES ('U15f925d86858', 'U2d94f2dd547e', 1, '2024-10-05 10:10:51.943324+00', '2024-10-05 10:10:51.943324+00');
INSERT INTO public.vote_user VALUES ('U15f925d86858', 'U286f94380611', 1, '2024-10-05 10:10:58.704257+00', '2024-10-05 10:10:58.704257+00');
INSERT INTO public.vote_user VALUES ('U15f925d86858', 'U2becfc64c13b', 1, '2024-10-05 10:11:03.879866+00', '2024-10-05 10:11:03.879866+00');
INSERT INTO public.vote_user VALUES ('U2d94f2dd547e', 'U15f925d86858', 1, '2024-10-05 10:11:22.941833+00', '2024-10-05 10:11:22.941833+00');
INSERT INTO public.vote_user VALUES ('U2d94f2dd547e', 'U286f94380611', 1, '2024-10-05 10:11:35.632028+00', '2024-10-05 10:11:35.632028+00');
INSERT INTO public.vote_user VALUES ('U2d94f2dd547e', 'U2becfc64c13b', 1, '2024-10-05 10:11:42.901754+00', '2024-10-05 10:11:42.901754+00');
INSERT INTO public.vote_user VALUES ('Ub8eac19792cf', 'U0679e218a6e4', 1, '2024-10-05 10:12:04.209625+00', '2024-10-05 10:12:04.209625+00');
INSERT INTO public.vote_user VALUES ('Ub8eac19792cf', 'Ud5a151749e32', 1, '2024-10-05 10:12:10.697902+00', '2024-10-05 10:12:10.697902+00');
INSERT INTO public.vote_user VALUES ('Ub8eac19792cf', 'U286f94380611', 1, '2024-10-05 10:12:16.692404+00', '2024-10-05 10:12:16.692404+00');
INSERT INTO public.vote_user VALUES ('Ub8eac19792cf', 'U2becfc64c13b', 1, '2024-10-05 10:12:21.450522+00', '2024-10-05 10:12:21.450522+00');
INSERT INTO public.vote_user VALUES ('U0679e218a6e4', 'Ub8eac19792cf', 1, '2024-10-05 10:12:38.399255+00', '2024-10-05 10:12:38.399255+00');
INSERT INTO public.vote_user VALUES ('U0679e218a6e4', 'Ud5a151749e32', 1, '2024-10-05 10:12:43.796187+00', '2024-10-05 10:12:43.796187+00');
INSERT INTO public.vote_user VALUES ('U0679e218a6e4', 'U286f94380611', 1, '2024-10-05 10:12:52.29169+00', '2024-10-05 10:12:52.29169+00');
INSERT INTO public.vote_user VALUES ('U0679e218a6e4', 'U2becfc64c13b', 1, '2024-10-05 10:12:59.161865+00', '2024-10-05 10:12:59.161865+00');
INSERT INTO public.vote_user VALUES ('Ud5a151749e32', 'U0679e218a6e4', 1, '2024-10-05 10:13:29.624077+00', '2024-10-05 10:13:29.624077+00');
INSERT INTO public.vote_user VALUES ('Ud5a151749e32', 'Ub8eac19792cf', 1, '2024-10-05 10:13:36.099853+00', '2024-10-05 10:13:36.099853+00');
INSERT INTO public.vote_user VALUES ('Ud5a151749e32', 'U286f94380611', 1, '2024-10-05 10:13:43.134387+00', '2024-10-05 10:13:43.134387+00');
INSERT INTO public.vote_user VALUES ('Ud5a151749e32', 'U2becfc64c13b', 1, '2024-10-05 10:13:48.809532+00', '2024-10-05 10:13:48.809532+00');
INSERT INTO public.vote_user VALUES ('U050e67479957', 'U6301c73d1354', 1, '2024-10-05 10:14:28.75143+00', '2024-10-05 10:14:28.75143+00');
INSERT INTO public.vote_user VALUES ('U050e67479957', 'U286f94380611', 1, '2024-10-05 10:14:38.545719+00', '2024-10-05 10:14:38.545719+00');
INSERT INTO public.vote_user VALUES ('U050e67479957', 'U2becfc64c13b', 1, '2024-10-05 10:14:44.172518+00', '2024-10-05 10:14:44.172518+00');
INSERT INTO public.vote_user VALUES ('U050e67479957', 'U7aa6bd888278', 1, '2024-10-05 10:14:51.572666+00', '2024-10-05 10:14:51.572666+00');
INSERT INTO public.vote_user VALUES ('U050e67479957', 'Ub0100d7bad5f', 1, '2024-10-05 10:14:56.108776+00', '2024-10-05 10:14:56.108776+00');
INSERT INTO public.vote_user VALUES ('U6301c73d1354', 'U050e67479957', 1, '2024-10-05 10:15:09.01398+00', '2024-10-05 10:15:09.01398+00');
INSERT INTO public.vote_user VALUES ('U6301c73d1354', 'Ub0100d7bad5f', 1, '2024-10-05 10:15:16.292941+00', '2024-10-05 10:15:16.292941+00');
INSERT INTO public.vote_user VALUES ('U6301c73d1354', 'U7aa6bd888278', 1, '2024-10-05 10:15:23.978398+00', '2024-10-05 10:15:23.978398+00');
INSERT INTO public.vote_user VALUES ('U6301c73d1354', 'U286f94380611', 1, '2024-10-05 10:15:57.475363+00', '2024-10-05 10:15:57.475363+00');
INSERT INTO public.vote_user VALUES ('U6301c73d1354', 'U2becfc64c13b', 1, '2024-10-05 10:16:03.466903+00', '2024-10-05 10:16:03.466903+00');
INSERT INTO public.vote_user VALUES ('U8ebde6fbfd3f', 'U286f94380611', 1, '2024-10-05 10:16:28.175482+00', '2024-10-05 10:16:28.175482+00');
INSERT INTO public.vote_user VALUES ('Ub13c4a82ab30', 'U2becfc64c13b', 1, '2024-10-05 10:16:46.11478+00', '2024-10-05 10:16:46.11478+00');
INSERT INTO public.vote_user VALUES ('Ub13c4a82ab30', 'U4d9267c70eab', 1, '2024-10-05 10:16:53.03461+00', '2024-10-05 10:16:53.03461+00');
INSERT INTO public.vote_user VALUES ('Ub13c4a82ab30', 'Ud14e4cfed365', 1, '2024-10-05 10:17:07.831035+00', '2024-10-05 10:17:07.831035+00');
INSERT INTO public.vote_user VALUES ('Ud14e4cfed365', 'U2becfc64c13b', 1, '2024-10-05 10:17:22.090965+00', '2024-10-05 10:17:22.090965+00');
INSERT INTO public.vote_user VALUES ('U3ffe5ced51de', 'U54c3f9996693', 1, '2024-10-05 10:17:43.403266+00', '2024-10-05 10:17:43.403266+00');
INSERT INTO public.vote_user VALUES ('U3ffe5ced51de', 'U3a33697ffab9', 1, '2024-10-05 10:18:01.423892+00', '2024-10-05 10:18:01.423892+00');
INSERT INTO public.vote_user VALUES ('U3ffe5ced51de', 'U2becfc64c13b', 1, '2024-10-05 10:18:10.393166+00', '2024-10-05 10:18:10.393166+00');
INSERT INTO public.vote_user VALUES ('U3ffe5ced51de', 'Ue479f7b03b5d', 1, '2024-10-05 10:18:17.397325+00', '2024-10-05 10:18:17.397325+00');
INSERT INTO public.vote_user VALUES ('U54c3f9996693', 'U2becfc64c13b', 1, '2024-10-05 10:18:43.533284+00', '2024-10-05 10:18:43.533284+00');
INSERT INTO public.vote_user VALUES ('U54c3f9996693', 'U3ffe5ced51de', 1, '2024-10-05 10:19:16.849166+00', '2024-10-05 10:19:16.849166+00');
INSERT INTO public.vote_user VALUES ('U36906cde6568', 'U3a33697ffab9', 1, '2024-10-05 10:19:38.747689+00', '2024-10-05 10:19:38.747689+00');
INSERT INTO public.vote_user VALUES ('U41906748a800', 'U4d9267c70eab', 1, '2024-12-09 15:58:35.131569+00', '2024-12-09 15:58:35.131569+00');
INSERT INTO public.vote_user VALUES ('U286f94380611', 'U7aa6bd888278', 1, '2024-10-03 08:09:45.710016+00', '2024-10-03 08:09:45.710016+00');
INSERT INTO public.vote_user VALUES ('U286f94380611', 'U3a33697ffab9', 1, '2024-10-05 09:50:36.569741+00', '2024-10-05 09:50:36.569741+00');
INSERT INTO public.vote_user VALUES ('U286f94380611', 'U2becfc64c13b', 1, '2024-10-05 09:50:52.457427+00', '2024-10-05 09:50:52.457427+00');
INSERT INTO public.vote_user VALUES ('U286f94380611', 'U6301c73d1354', 1, '2024-10-05 09:51:40.074698+00', '2024-10-05 09:51:40.074698+00');
INSERT INTO public.vote_user VALUES ('U286f94380611', 'U050e67479957', 1, '2024-10-05 09:52:46.765364+00', '2024-10-05 09:52:46.765364+00');
INSERT INTO public.vote_user VALUES ('U286f94380611', 'U8ebde6fbfd3f', 1, '2024-10-05 09:53:03.383864+00', '2024-10-05 09:53:03.383864+00');
INSERT INTO public.vote_user VALUES ('U8c85f8c3bef7', 'U41906748a800', 1, '2024-10-05 09:53:40.500053+00', '2024-10-05 09:53:40.500053+00');
INSERT INTO public.vote_user VALUES ('U7aa6bd888278', 'U3a33697ffab9', 1, '2024-10-05 09:54:06.446317+00', '2024-10-05 09:54:06.446317+00');
INSERT INTO public.vote_user VALUES ('U7aa6bd888278', 'U2becfc64c13b', 1, '2024-10-05 09:54:26.73466+00', '2024-10-05 09:54:26.73466+00');
INSERT INTO public.vote_user VALUES ('U2d94f2dd547e', 'Uffbd6f094f6a', 1, '2024-10-05 10:11:29.256573+00', '2024-10-05 10:11:29.256573+00');
INSERT INTO public.vote_user VALUES ('U7aa6bd888278', 'U286f94380611', 1, '2024-10-03 08:02:33.430895+00', '2024-10-05 09:55:27.889793+00');
INSERT INTO public.vote_user VALUES ('U7aa6bd888278', 'Ub0100d7bad5f', 1, '2024-10-05 09:55:47.558178+00', '2024-10-05 09:55:47.558178+00');
INSERT INTO public.vote_user VALUES ('U7aa6bd888278', 'U050e67479957', 1, '2024-10-05 09:56:04.844494+00', '2024-10-05 09:56:04.844494+00');
INSERT INTO public.vote_user VALUES ('U7aa6bd888278', 'U6301c73d1354', 1, '2024-10-05 09:56:12.000662+00', '2024-10-05 09:56:12.000662+00');
INSERT INTO public.vote_user VALUES ('U7aa6bd888278', 'U8ebde6fbfd3f', 1, '2024-10-05 09:56:18.427138+00', '2024-10-05 09:56:18.427138+00');
INSERT INTO public.vote_user VALUES ('U3a33697ffab9', 'U2becfc64c13b', 1, '2024-10-05 09:57:00.431325+00', '2024-10-05 09:57:00.431325+00');
INSERT INTO public.vote_user VALUES ('U3a33697ffab9', 'U286f94380611', 1, '2024-10-05 09:57:10.908413+00', '2024-10-05 09:57:10.908413+00');
INSERT INTO public.vote_user VALUES ('U3a33697ffab9', 'Ue479f7b03b5d', 1, '2024-10-05 09:57:18.635621+00', '2024-10-05 09:57:18.635621+00');
INSERT INTO public.vote_user VALUES ('U3a33697ffab9', 'Ue79d43c03425', 1, '2024-10-05 09:57:28.134755+00', '2024-10-05 09:57:28.134755+00');
INSERT INTO public.vote_user VALUES ('U3a33697ffab9', 'U7aa6bd888278', 1, '2024-10-05 09:57:37.499574+00', '2024-10-05 09:57:37.499574+00');
INSERT INTO public.vote_user VALUES ('U3a33697ffab9', 'Ub0100d7bad5f', 1, '2024-10-05 09:57:44.011136+00', '2024-10-05 09:57:44.011136+00');
INSERT INTO public.vote_user VALUES ('U3a33697ffab9', 'U28846d74623d', 1, '2024-10-05 09:57:49.235574+00', '2024-10-05 09:57:49.235574+00');
INSERT INTO public.vote_user VALUES ('U3a33697ffab9', 'Udab52ec61933', 1, '2024-10-05 09:57:55.946074+00', '2024-10-05 09:57:55.946074+00');
INSERT INTO public.vote_user VALUES ('U3a33697ffab9', 'Uffbd6f094f6a', 1, '2024-10-05 09:58:01.066848+00', '2024-10-05 09:58:01.066848+00');
INSERT INTO public.vote_user VALUES ('U3a33697ffab9', 'U15f925d86858', 1, '2024-10-05 09:58:08.77486+00', '2024-10-05 09:58:08.77486+00');
INSERT INTO public.vote_user VALUES ('U3a33697ffab9', 'U2d94f2dd547e', 1, '2024-10-05 09:58:14.426756+00', '2024-10-05 09:58:14.426756+00');
INSERT INTO public.vote_user VALUES ('U3a33697ffab9', 'Ub8eac19792cf', 1, '2024-10-05 09:58:19.28183+00', '2024-10-05 09:58:19.28183+00');
INSERT INTO public.vote_user VALUES ('U3a33697ffab9', 'U0679e218a6e4', 1, '2024-10-05 09:58:24.774371+00', '2024-10-05 09:58:24.774371+00');
INSERT INTO public.vote_user VALUES ('U3a33697ffab9', 'Ud5a151749e32', 1, '2024-10-05 09:58:29.952218+00', '2024-10-05 09:58:29.952218+00');
INSERT INTO public.vote_user VALUES ('U3a33697ffab9', 'U050e67479957', 1, '2024-10-05 09:58:35.240853+00', '2024-10-05 09:58:35.240853+00');
INSERT INTO public.vote_user VALUES ('U3a33697ffab9', 'U6301c73d1354', 1, '2024-10-05 09:58:41.356888+00', '2024-10-05 09:58:41.356888+00');
INSERT INTO public.vote_user VALUES ('U3a33697ffab9', 'U8ebde6fbfd3f', 1, '2024-10-05 09:58:47.288557+00', '2024-10-05 09:58:47.288557+00');
INSERT INTO public.vote_user VALUES ('U3a33697ffab9', 'U3ffe5ced51de', 1, '2024-10-05 09:59:21.567968+00', '2024-10-05 09:59:21.567968+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'U3a33697ffab9', 1, '2024-10-05 09:59:46.898249+00', '2024-10-05 09:59:46.898249+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'U4d9267c70eab', 1, '2024-10-05 09:59:58.277519+00', '2024-10-05 09:59:58.277519+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'U286f94380611', 1, '2024-10-05 10:00:05.675513+00', '2024-10-05 10:00:05.675513+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'U8c85f8c3bef7', 1, '2024-10-05 10:00:14.221975+00', '2024-10-05 10:00:14.221975+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'Ue479f7b03b5d', 1, '2024-10-05 10:00:20.739224+00', '2024-10-05 10:00:20.739224+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'U41906748a800', 1, '2024-10-05 10:00:29.58758+00', '2024-10-05 10:00:29.58758+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'Ue79d43c03425', 1, '2024-10-05 10:00:32.973659+00', '2024-10-05 10:00:32.973659+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'U7aa6bd888278', 1, '2024-10-05 10:00:39.00041+00', '2024-10-05 10:00:39.00041+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'Ub0100d7bad5f', 1, '2024-10-05 10:00:43.57799+00', '2024-10-05 10:00:43.57799+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'U28846d74623d', 1, '2024-10-05 10:00:52.004574+00', '2024-10-05 10:00:52.004574+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'Udab52ec61933', 1, '2024-10-05 10:00:58.225729+00', '2024-10-05 10:00:58.225729+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'Uffbd6f094f6a', 1, '2024-10-05 10:01:06.221342+00', '2024-10-05 10:01:06.221342+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'U15f925d86858', 1, '2024-10-05 10:01:12.658942+00', '2024-10-05 10:01:12.658942+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'U2d94f2dd547e', 1, '2024-10-05 10:01:17.745679+00', '2024-10-05 10:01:17.745679+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'Ub8eac19792cf', 1, '2024-10-05 10:01:22.458019+00', '2024-10-05 10:01:22.458019+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'U0679e218a6e4', 1, '2024-10-05 10:01:27.711278+00', '2024-10-05 10:01:27.711278+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'Ud5a151749e32', 1, '2024-10-05 10:01:32.898363+00', '2024-10-05 10:01:32.898363+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'U050e67479957', 1, '2024-10-05 10:01:39.340868+00', '2024-10-05 10:01:39.340868+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'U6301c73d1354', 1, '2024-10-05 10:01:44.458572+00', '2024-10-05 10:01:44.458572+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'U8ebde6fbfd3f', 1, '2024-10-05 10:01:49.452429+00', '2024-10-05 10:01:49.452429+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'Ub13c4a82ab30', 1, '2024-10-05 10:01:55.484123+00', '2024-10-05 10:01:55.484123+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'Ud14e4cfed365', 1, '2024-10-05 10:01:59.871309+00', '2024-10-05 10:01:59.871309+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'U3ffe5ced51de', 1, '2024-10-05 10:02:04.307502+00', '2024-10-05 10:02:04.307502+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'U54c3f9996693', 1, '2024-10-05 10:02:09.412555+00', '2024-10-05 10:02:09.412555+00');
INSERT INTO public.vote_user VALUES ('U2becfc64c13b', 'U36906cde6568', 1, '2024-10-05 10:02:14.232315+00', '2024-10-05 10:02:14.232315+00');
INSERT INTO public.vote_user VALUES ('U4d9267c70eab', 'U3a33697ffab9', 1, '2024-10-05 10:03:04.404736+00', '2024-10-05 10:03:04.404736+00');
INSERT INTO public.vote_user VALUES ('U4d9267c70eab', 'U41906748a800', 1, '2024-10-05 10:03:21.361035+00', '2024-10-05 10:03:21.361035+00');
INSERT INTO public.vote_user VALUES ('U4d9267c70eab', 'U286f94380611', 1, '2024-10-05 10:03:28.863649+00', '2024-10-05 10:03:28.863649+00');
INSERT INTO public.vote_user VALUES ('U4d9267c70eab', 'Ub13c4a82ab30', 1, '2024-10-05 10:03:38.139133+00', '2024-10-05 10:03:38.139133+00');
INSERT INTO public.vote_user VALUES ('U4d9267c70eab', 'Ud14e4cfed365', 1, '2024-10-05 10:03:44.381566+00', '2024-10-05 10:03:44.381566+00');


--
-- PostgreSQL database dump complete
--

