/**
 * @Author  : Ahn Jin Young
 * @ID 		: 2022-15804
 * @ref 	: Sorting algorithms are based on Textbook pesudo code.
 */


import java.io.*;
import java.util.*;

public class SortingTest
{
	static int k;
	static float k_collision;
	static float k_sorted;
	//private static final int QUICK_INSERTION_THRESHOLD = 16; //for small subarray insertion sort
	public static void main(String args[])
	{
		BufferedReader br = new BufferedReader(new InputStreamReader(System.in));

		try
		{
			boolean isRandom = false;
			int[] value;	
			String nums = br.readLine();	
			if (nums.charAt(0) == 'r')
			{
			
				isRandom = true;	

				String[] nums_arg = nums.split(" ");

				int numsize = Integer.parseInt(nums_arg[1]);
				int rminimum = Integer.parseInt(nums_arg[2]);	
				int rmaximum = Integer.parseInt(nums_arg[3]);	

				Random rand = new Random();	// ?�수 ?�스?�스�??�성?�다.

				value = new int[numsize];	// 배열???�성?�다.
				for (int i = 0; i < value.length; i++)	// 각각??배열???�수�??�성?�여 ?�??
					value[i] = rand.nextInt(rmaximum - rminimum + 1) + rminimum;
			}
			else
			{
				// ?�수가 ?�닐 경우
				int numsize = Integer.parseInt(nums);

				value = new int[numsize];	// 배열???�성?�다.
				for (int i = 0; i < value.length; i++)	// ?�줄???�력받아 배열?�소�??�??
					value[i] = Integer.parseInt(br.readLine());
			}

			// ?�자 ?�력????받았?��?�??�렬 방법??받아 그에 맞는 ?�렬???�행?�다.
			while (true)
			{
				int[] newvalue = (int[])value.clone();	// ?�래 값의 보호�??�해 복사본을 ?�성?�다.
                char algo = ' ';

				if (args.length == 4) {
                    return;
                }
				
				//k = Integer.parseInt(args[0]); // Find optimal k

				String command = args.length > 0 ? args[0] : br.readLine();

				if (args.length > 0) {
                    args = new String[4];
                }
				
				long t = System.currentTimeMillis();
				switch (command.charAt(0))
				{
					case 'B':	// Bubble Sort
						newvalue = DoBubbleSort(newvalue);
						break;
					case 'I':	// Insertion Sort
						newvalue = DoInsertionSort(newvalue);
						break;
					case 'H':	// Heap Sort
						newvalue = DoHeapSort(newvalue);
						break;
					case 'M':	// Merge Sort
						newvalue = DoMergeSort(newvalue);
						break;
					case 'Q':	// Quick Sort
						newvalue = DoQuickSort(newvalue);
						break;
					case 'R':	// Radix Sort
						newvalue = DoRadixSort(newvalue);
						break;
					case 'S':	// Search
						algo = DoSearch(newvalue);
						break;
					case 'X':
						return;
					default:
						throw new IOException("?�못???�렬 방법???�력?�습?�다.");
				}
				if (isRandom)
				{
			
					System.out.println((System.currentTimeMillis() - t) + " ms");
				}
				else
				{
	
                    if (command.charAt(0) != 'S') {
                        for (int i = 0; i < newvalue.length; i++) {
                            System.out.println(newvalue[i]);
                        }
                    } else {
                        System.out.println(algo);
                    }
				}

			}
		}
		catch (IOException e)
		{
			System.out.println("?�력???�못?�었?�니?? ?�류 : " + e.toString());
		}
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////
	private static int[] DoBubbleSort(int[] value)
	{
		if (value == null || value.length < 2)
		{
			return (value);
		}

		int n = value.length;

		while (n > 1)
		{
			int lastSwap = 0;

			for (int i = 1; i < n; i++)
			{
				if (value[i - 1] > value[i])
				{
					int temp = value[i];
					value[i] = value[i - 1];
					value[i - 1] = temp;
					lastSwap = i;
				}
			}

			if (lastSwap == 0)
			{
				break;
			}

			n = lastSwap;
		}

		return (value);
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////
		private static int[] DoInsertionSort(int[] value)
	{
		if (value == null || value.length < 2) {
			return (value);
		}

		for (int i = 1; i < value.length; i++) {
			int key = value[i];
			int j = i - 1;
			while (j >= 0 && value[j] > key) {
				value[j + 1] = value[j];
				j--;
			}
			value[j + 1] = key;
		}

		return (value);
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////
	private static int[] DoHeapSort(int[] value) {
		int n = value.length;
	
		buildMaxHeap(value, n);
	
		for (int i = n - 1; i > 0; i--) {
			swap(value, 0, i);
	
			procolateDown(value, i, 0);
		}
		return value;
	}
	
	
	private static void buildMaxHeap(int[] arr, int n) {
		for (int i = (n / 2) - 1; i >= 0; i--) {
			procolateDown(arr, n, i);
		}
	}
	
	private static void procolateDown(int[] arr, int n, int i) {
		int root = i; 
		int left = (2 * i) + 1; 
		int right = (2 * i) + 2; 
	
		if (left < n && arr[left] > arr[root]) {
			root = left;
		}
	
		if (right < n && arr[right] > arr[root]) {
			root = right;
		}
	   
		if (root != i) {
			swap(arr, i, root);
			procolateDown(arr, n, root);
		}
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////
	private static int[] DoMergeSort(int[] value)
	{
		mergeSort(value);
		return value;
	}


static void mergeSort(int[] arr) { //need buffer 
    int[] buffer = new int[arr.length];
    mergeSort(arr, buffer, 0, arr.length - 1);
}

private static void mergeSort(int[] arr, int[] buffer, int left, int right) {

    if (left >= right) return;
    int mid = (left + right) >>> 1;

    mergeSort(arr, buffer, left, mid);
    mergeSort(arr, buffer, mid + 1, right);

    if (arr[mid] <= arr[mid + 1]) return;

    merge(arr, buffer, left, mid, right);
}

private static void merge(int[] arr, int[] buffer, int left, int mid, int right) {
    System.arraycopy(arr, left, buffer, left, mid - left + 1);

    int i = left;     
    int j = mid + 1;   
    int k = left;     

    while (i <= mid && j <= right) {
        if (buffer[i] <= arr[j]) arr[k++] = buffer[i++];
        else                     arr[k++] = arr[j++];
    }
    while (i <= mid) arr[k++] = buffer[i++];
}
	////////////////////////////////////////////////////////////////////////////////////////////////////
		private static int[] DoQuickSort(int[] value)
	{
		if (value == null || value.length < 2) {
			return value;
		}

		quickSort(value, 0, value.length - 1);
		return value;
	}

	private static void quickSort(int[] arr, int low, int high) {
		/* 
		while (high - low > QUICK_INSERTION_THRESHOLD) {
			int pivot = partition(arr, low, high);

			if (pivot - low + 1 < high - pivot) {
				quickSort(arr, low, pivot);
				low = pivot + 1;
			} else {
				quickSort(arr, pivot + 1, high);
				high = pivot;
			}
		}

		insertionSort(arr, low, high);
		int pivot = partition(arr, low, high);

		if (pivot - low + 1 < high - pivot) {
			quickSort(arr, low, pivot);
			low = pivot + 1;
		} else {
			quickSort(arr, pivot + 1, high);
			high = pivot;
		}
		*/
		if (low >= high) return;
		int mid = partition(arr, low, high);
		quickSort(arr, low, mid-1);
		quickSort(arr, mid+1, high);


	}

	private static int partition(int[] arr, int low, int high) {
		int pivot = arr[high];
		int i = low - 1;
	
		for (int j = low; j < high; j++) {
			if (arr[j] <= pivot) {
				i++;
				// inline swap(arr, i, j)
				int t = arr[i]; arr[i] = arr[j]; arr[j] = t;
			}
		}
		// pivot을 제자리로
		int t = arr[i + 1]; arr[i + 1] = arr[high]; arr[high] = t;
		return i + 1; // pivot의 최종 위치
	}
	private static void insertionSort(int[] arr, int low, int high) {
		if (low >= high) {
			return;
		}
		for (int i = low + 1; i <= high; i++) {
			int key = arr[i];
			int j = i - 1;

			while (j >= low && arr[j] > key) {
				arr[j + 1] = arr[j];
				j--;
			}

			arr[j + 1] = key;
		}
	}

	private static void swap(int[] arr, int i, int j) {
		int tmp = arr[i];
		arr[i] = arr[j];
		arr[j] = tmp;
	}

	// ref : https://banjjak1.tistory.com/52 
	// modified in my style
	private static int[] DoRadixSort(int[] value) {
		if (value == null || value.length <= 1) return value;
	

		int numDigits = maxDigits(value);
	
		// LSD passes on absolute values
		int pow = 1;
		for (int pass = 0; pass < numDigits; pass++) {

			@SuppressWarnings("unchecked")
			ArrayList<Integer>[] buckets = new ArrayList[10];
			for (int i = 0; i < 10; i++) buckets[i] = new ArrayList<>();
	
			for (int x : value) {
				int ax = (x >= 0) ? x : -x;       
				int digit = (int) ((ax / pow) % 10);
				buckets[digit].add(x);
			}
	
			int idx = 0;
			for (int d = 0; d < 10; d++) {
				for (int x : buckets[d]) value[idx++] = x;
			}
	
			pow *= 10;
		}
	
		int n = value.length;
		int[] neg = new int[n];
		int[] pos = new int[n];
		int ni = 0, pi = 0;
		for (int x : value) {
			if (x < 0) neg[ni++] = x;
			else       pos[pi++] = x;
		}

		for (int i = 0; i < ni / 2; i++) {
			int t = neg[i];
			neg[i] = neg[ni - 1 - i];
			neg[ni - 1 - i] = t;
		}

		int w = 0;
		for (int i = 0; i < ni; i++) value[w++] = neg[i];
		for (int i = 0; i < pi; i++) value[w++] = pos[i];
	
		return value;
	}
	////////////////////////////////////////////////////////////////////////////////////////////////////
    private static char DoSearch(int[] value)
	{

		int digits = maxDigits(value);
		if (digits <= k) return 'R';

		if (collisionRatio(value) > k_collision) return 'I';

		if (sortedRatio(value) > k_sorted) return 'I';



		return ('Q'); 
	}

	/* ====================== utility functions ====================== */

	private static int maxDigits(int[] arr) {
		int maxDigits = 0;
		for (int n : arr) {
			int x = n;
			if (x == Integer.MIN_VALUE) x = Integer.MAX_VALUE; // abs overflow 보정
	
			x = (x < 0) ? -x : x; 
			int digits = 1;
	
			if (x >= 10) digits = 2;
			if (x >= 100) digits = 3;
			if (x >= 1000) digits = 4;
			if (x >= 10000) digits = 5;
			if (x >= 100000) digits = 6;
			if (x >= 1000000) digits = 7;
			if (x >= 10000000) digits = 8;
			if (x >= 100000000) digits = 9;
			if (x >= 1000000000) digits = 10;
	
			if (digits > maxDigits) maxDigits = digits;
		}
		return maxDigits;
	}


	private static float collisionRatio(int[] value) {
		Map<Integer, Integer> freq = new HashMap<>(value.length * 2);
		int duplicates = 0;
	
		for (int v : value) {
			Integer old = freq.put(v, 1);
			if (old != null) {
				duplicates++;
			}
		}
	
		return (float) duplicates / value.length;
	}

	private static float sortedRatio(int[] value) {
		int sortCnt = 0;
		for (int i = 0; i < value.length-1; i++) {
			if (value[i] <= value[i+1]) sortCnt++; 
		}
		return (float) sortCnt / value.length;
	}


	
}

