(constraint
  (and
    (forall ((x_ (BitVec Size4)) ((x_ = (lit "#b1000" (BitVec Size4)))))
      (forall ((y_ (BitVec Size4)) ((y_ = (app (_ rotate_right 7) x_))))
        (forall ((z_ (BitVec Size4)) ((z_ = (lit "#b0001" (BitVec Size4)))))
            ((y_ =  z_))
        )
      )
    )
    (forall ((x (BitVec Size32)) (true))
      (forall ((y (BitVec Size32)) ((x = y)))
    	  (((app (_ sign_extend 64) x) = (app (_ sign_extend 64) y)))
      )
    )
  )
)